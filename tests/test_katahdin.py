"""The Katahdin plant, driven as a scada drives it: relays in, channel
readings out. The house is larch, the layout ta-katahdin-layout makes from
hazel's; a house with no boiler or another count of zones is made the
same way, in memory."""

import json
import math
import time
from collections.abc import Iterator, Mapping
from pathlib import Path

import pytest
from gwbase.transport_encoding import WrappedRoutingEnvelope
from gwbase.wrapped import unwrap_bytes, wrap_bytes
from test_plant import Listener

from gwta.config import GwtaSettings
from gwta.fmu_model import ENCODER_BY_UNIT_AND_TELEMETRY, FmuPlantModel, RelayEffect
from gwta.hello import provision_topology, wait_for_consuming
from gwta.katahdin import effect_by_relay, katahdin_model, variable_by_channel
from gwta.katahdin_layout import katahdin_layout, load_house0
from gwta.plant import SimulatedPlant, actuation_binding_key, lrh, write_g_node_json
from gwta.plant_layout import PlantLayout, load_plant_layout, plant_layout
from gwta.sema.codec import SemaCodec
from gwta.sema.enums import ChangeRelayPin, RelayClosedOrOpen, TelemetryName
from gwta.sema.types import (
    BoilerBackup,
    I2cRelayComponentGt,
    KatahdinLayout,
    RelayControlConfig,
    SimPlantActuation,
    SimPlantFlux,
)
from gwta.sensing import device_encodings, pulse_microhertz, thermistor_microvolts

FMU_PATH = Path(__file__).parent.parent / "build" / "KatahdinPlant.fmu"
CONFIG = Path(__file__).parent / "config"
HAZEL_PATH = CONFIG / "gw.house0.no.sieg.hazel.layout.json"
LARCH_PATH = CONFIG / "gw.katahdin.larch.layout.json"
LARCH_ALIAS = "d1.isone.ct.newhaven.larch1"
START_MS = 1_794_300_000_000
ZONES = ("north", "south", "east", "west")

FLOWS = ("primary-flow", "secondary-flow", "dist-flow", "store-flow")
FLOW_PULSES = ("primary-flow-hz", "dist-flow-hz", "store-flow-hz")
TANK_DEPTHS = tuple(
    f"tank{tank}-depth{depth}-device" for tank in (1, 2, 3) for depth in (1, 2, 3)
)
TANK_VOLTAGES = tuple(
    f"tank{tank}-depth{depth}-micro-v" for tank in (1, 2, 3) for depth in (1, 2, 3)
)
CHARGING = ("v1-hx-house-relay", "secondary-pump-relay", "hp-scada-ops-relay")

WARM_ZONES = {"TStartZone": 295.15}
COLD_ZONES = {"TStartZone": 291.15}


def larch(boiler: bool = True, zones: tuple[str, ...] = ZONES) -> KatahdinLayout:
    return katahdin_layout(
        load_house0(HAZEL_PATH), ltn_alias=LARCH_ALIAS, zones=zones, boiler=boiler
    )


def layout(boiler: bool = True, zones: tuple[str, ...] = ZONES) -> PlantLayout:
    if boiler and zones == ZONES:
        return load_plant_layout(LARCH_PATH)
    return plant_layout(larch(boiler, zones))


class Bench:
    """One plant and the clock it is stepped by. A scada in charge holds
    the heat pump's call itself and makes none until a test closes the
    call's relay; with none in charge every relay is de-energized."""

    def __init__(
        self,
        overrides: Mapping[str, float],
        boiler: bool = True,
        tick_s: int = 60,
        scada_in_charge: bool = True,
    ) -> None:
        if not FMU_PATH.exists():
            pytest.fail(f"{FMU_PATH} is missing: run scripts/build_fmu.sh")
        self.layout = layout(boiler)
        self.model = katahdin_model(
            fmu_path=FMU_PATH,
            layout=self.layout,
            overrides=overrides,
            start_ms=START_MS,
        )
        self.now_ms = START_MS
        self.tick_s = tick_s
        self.history: list[dict[str, int]] = []
        if scada_in_charge:
            backup = self.layout.hydronic.backup
            if isinstance(backup, BoilerBackup):
                self.energize(backup.failsafe_relay_name)
            self.open("hp-scada-ops-relay")

    def actuate(self, relay: str, action: ChangeRelayPin) -> None:
        self.model.actuate(
            SimPlantActuation(
                relay_name=relay,
                action=action,
                actuation_time_unix_ms=self.now_ms,
                actual_time_utc="2026-11-11T15:00:00.000Z",
            )
        )

    def energize(self, *relays: str) -> None:
        for relay in relays:
            self.actuate(relay, ChangeRelayPin.Energize)

    def set_contact(self, relay: str, state: RelayClosedOrOpen) -> None:
        energized = self.layout.config_by_relay[relay].energized_state == state.value
        self.actuate(
            relay, ChangeRelayPin.Energize if energized else ChangeRelayPin.DeEnergize
        )

    def close(self, *relays: str) -> None:
        for relay in relays:
            self.set_contact(relay, RelayClosedOrOpen.RelayClosed)

    def open(self, *relays: str) -> None:
        for relay in relays:
            self.set_contact(relay, RelayClosedOrOpen.RelayOpen)

    def run(self, seconds: int) -> dict[str, int]:
        end_ms = self.now_ms + seconds * 1000
        while self.now_ms < end_ms:
            self.now_ms = min(self.now_ms + self.tick_s * 1000, end_ms)
            self.history.append(self.model.step(self.now_ms))
        return self.history[-1]

    def energy_imbalance(self, initial_energy: float) -> float:
        return (self.model.read("thermalEnergy") - initial_energy) - (
            self.model.read("heatPumpEnergy") - self.model.read("lossEnergy")
        )


@pytest.fixture
def bench() -> Iterator[list[Bench]]:
    """Benches a test opens, closed when it ends."""
    opened: list[Bench] = []
    yield opened
    for one in opened:
        one.model.close()


def open_bench(
    opened: list[Bench],
    overrides: Mapping[str, float],
    boiler: bool = True,
    tick_s: int = 60,
    scada_in_charge: bool = True,
) -> Bench:
    opened.append(Bench(overrides, boiler, tick_s, scada_in_charge))
    return opened[-1]


def test_the_larch_layout_is_what_its_generator_makes_from_hazel() -> None:
    assert json.loads(LARCH_PATH.read_text()) == json.loads(
        json.dumps(larch().to_dict())
    )


def test_a_house_with_no_boiler_has_no_backup_and_no_boiler_valve() -> None:
    without = larch(boiler=False)
    assert without.hydronic.backup is None
    names = {node.name for node in without.sh_nodes}
    assert names == {node.name for node in larch().sh_nodes} - {
        "backup",
        "hp-failsafe-relay",
        "aquastat-ctrl-relay",
        "v5-boiler-relay",
    }


def test_every_relay_of_the_house_is_on_a_board_relay_of_its_own() -> None:
    relay_by_node = {
        config.actor_name: component.relay_name
        for component in larch().components
        if isinstance(component, I2cRelayComponentGt)
        for config in component.config_list
    }
    assert set(relay_by_node) == layout().relay_names
    assert len(set(relay_by_node.values())) == len(relay_by_node) == 18


def test_every_katahdin_channel_reads_an_fmu_output() -> None:
    variables = variable_by_channel(layout().hydronic)
    assert variables["hp-lwt"] == "hpLwt"
    assert variables["store-flow"] == "storeFlow"
    assert variables["tank1-depth1"] == "tankDepth[1,1]"
    assert variables["tank3-depth3"] == "tankDepth[3,3]"
    assert variables["tank2-depth1-device"] == "tankDepth[2,1]"
    assert variables["tank2-depth1-micro-v"] == "tankDepth[2,1]"
    assert variables["dist-flow-hz"] == "distFlow"
    assert variables["zone2-south-whitewire-pwr"] == "zoneCallPower[2]"
    assert variables["zone4-west-temp"] == "zoneTemperature[4]"
    assert set(layout().telemetry_by_channel) <= set(variables)


def test_relays_rest_where_the_houses_failsafe_needs_them() -> None:
    with_boiler = effect_by_relay(layout())
    without = effect_by_relay(layout(boiler=False))
    resting = {
        relay: (effect.variable, effect.de_energized)
        for relay, effect in with_boiler.items()
    }
    assert resting == {
        "v1-hx-house-relay": ("v1Position", 0.0),
        "v2-store-hot-relay": ("v2Position", 1.0),
        "v3-store-cold-relay": ("v3Position", 0.0),
        "v4-house-return-relay": ("v4Position", 0.0),
        "v5-boiler-relay": ("v5Position", 1.0),
        "secondary-pump-relay": ("secondaryPumpOn", 0.0),
        "hp-scada-ops-relay": ("hpEnable", 1.0),
        "hp-failsafe-relay": ("hpScadaControl", 0.0),
    }
    assert without["v4-house-return-relay"] == RelayEffect("v4Position", 0.0, 1.0)
    assert "v5-boiler-relay" not in without
    assert "hp-failsafe-relay" not in without
    for effect in (*with_boiler.values(), *without.values()):
        assert {effect.energized, effect.de_energized} == {0.0, 1.0}


def rewired(config: RelayControlConfig, **fields: str) -> RelayControlConfig:
    return RelayControlConfig.model_validate(config.model_dump() | fields)


def test_a_relay_closes_its_contact_in_the_position_the_layout_gives_it() -> None:
    katahdin = layout()
    pump = katahdin.config_by_relay["secondary-pump-relay"]
    call = katahdin.config_by_relay["hp-scada-ops-relay"]
    assert (pump.energized_state, call.energized_state) == ("RelayClosed", "RelayOpen")
    swapped = katahdin._replace(
        config_by_relay=katahdin.config_by_relay
        | {
            "secondary-pump-relay": rewired(
                pump,
                wiring_config=call.wiring_config,
                energizing_event=call.energizing_event,
                de_energizing_event=call.de_energizing_event,
                energized_state=call.energized_state,
                de_energized_state=call.de_energized_state,
            )
        }
    )
    assert effect_by_relay(katahdin)["secondary-pump-relay"] == RelayEffect(
        "secondaryPumpOn", energized=1.0, de_energized=0.0
    )
    assert effect_by_relay(swapped)["secondary-pump-relay"] == RelayEffect(
        "secondaryPumpOn", energized=0.0, de_energized=1.0
    )


@pytest.mark.parametrize("relay", ["v1-hx-house-relay", "hp-scada-ops-relay"])
def test_a_relay_whose_closing_position_the_layout_does_not_give_is_refused(
    relay: str,
) -> None:
    katahdin = layout()
    failsafe = katahdin.config_by_relay["hp-failsafe-relay"]
    message = f"does not say which position of {relay} closes its contact"
    for configs in (
        {name: c for name, c in katahdin.config_by_relay.items() if name != relay},
        katahdin.config_by_relay | {relay: failsafe},
    ):
        with pytest.raises(ValueError, match=message):
            effect_by_relay(katahdin._replace(config_by_relay=configs))


@pytest.mark.parametrize(
    ("unit", "telemetry", "value", "encoded"),
    [
        ("K", TelemetryName.CelsiusTimes100, 321.65, 4850),
        ("K", TelemetryName.WaterTempCTimes1000, 321.65, 48500),
        ("K", TelemetryName.AirTempCTimes1000, 293.15, 20000),
        ("m3/s", TelemetryName.GpmTimes100, 3.15451e-4, 500),
        ("W", TelemetryName.PowerW, 3214.6, 3215),
    ],
)
def test_si_values_are_encoded_as_their_channel_reads(
    unit: str, telemetry: TelemetryName, value: float, encoded: int
) -> None:
    assert ENCODER_BY_UNIT_AND_TELEMETRY[(unit, telemetry)](value) == encoded


def test_a_thermistor_voltage_reads_back_as_the_water_it_stands_in() -> None:
    microvolts = thermistor_microvolts(3977)(273.15 + 50)
    volts = microvolts / 1e6
    kohms = 5.65 * volts / (3.3 - volts)
    assert 1 / (1 / 298 + math.log(kohms / 10) / 3977) - 273 == pytest.approx(
        50, abs=0.001
    )
    assert thermistor_microvolts(3977)(298.15) == 2_108_626


def test_a_pulse_rate_is_the_flow_over_the_meters_gallons_per_pulse() -> None:
    assert pulse_microhertz(0.0009)(5 * 6.30902e-5) == 92_592_593
    assert pulse_microhertz(0.0009)(0.0) == 0


def test_a_sensors_own_reading_is_encoded_as_that_sensor_does() -> None:
    encodings = device_encodings(layout())
    assert set(encodings) == set(TANK_VOLTAGES + FLOW_PULSES)
    assert {encodings[name].unit for name in TANK_VOLTAGES} == {"K"}
    assert {encodings[name].unit for name in FLOW_PULSES} == {"m3/s"}


@pytest.mark.fmu
def test_a_tank_voltage_and_a_pulse_rate_follow_the_water(bench: list[Bench]) -> None:
    plant = open_bench(bench, WARM_ZONES)
    plant.close(*CHARGING)
    values = plant.run(20 * 60)
    for depth, voltage in zip(TANK_DEPTHS, TANK_VOLTAGES, strict=True):
        kelvin = plant.model.read(variable_by_channel(layout().hydronic)[depth])
        assert values[voltage] == thermistor_microvolts(3977)(kelvin)
    assert values["tank1-depth1-micro-v"] < values["tank3-depth3-micro-v"]
    assert values["store-flow-hz"] == pytest.approx(
        values["store-flow"] / 100 / 60 / 0.0009 * 1e6, rel=2e-3
    )
    assert values["dist-flow-hz"] == 0
    assert values["primary-flow-hz"] > 90_000_000


@pytest.mark.fmu
def test_a_plant_at_rest_reports_every_channel_and_moves_no_water(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, WARM_ZONES)
    values = plant.run(60)
    assert list(values) == list(layout().telemetry_by_channel)
    assert [values[name] for name in FLOWS] == [0, 0, 0, 0]
    assert values["hp-odu-pwr"] == 20
    assert values["tank2-depth2-device"] == 3000
    assert values["zone1-north-temp"] in range(2190, 2201)


@pytest.mark.fmu
def test_heat_store_from_hp_sends_the_whole_secondary_flow_down_the_store(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, WARM_ZONES)
    plant.close(*CHARGING)
    values = plant.run(20 * 60)
    assert values["secondary-flow"] in range(490, 511)
    assert values["store-flow"] == values["secondary-flow"]
    assert values["primary-flow"] == 500
    assert values["dist-flow"] == 0
    assert values["hp-odu-pwr"] in range(3000, 5001)
    assert values["hp-lwt"] > values["secondary-lwt"] > values["secondary-ewt"]
    assert values["tank1-depth1-device"] > 3400
    assert values["tank3-depth3-device"] in range(2995, 3006)
    assert plant.model.read("storeCharge") > 0


@pytest.mark.fmu
def test_heat_house_from_hp_leaves_the_store_what_the_house_does_not_take(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, COLD_ZONES)
    plant.close(*CHARGING, "v4-house-return-relay", "v5-boiler-relay")
    values = plant.run(20 * 60)
    assert values["secondary-flow"] in range(490, 541)
    assert values["dist-flow"] in range(480, 531)
    assert values["store-flow"] == 0
    surplus = plant.model.read("storeCharge")
    assert 0 < surplus < plant.model.read("VFlowMeterMin")
    assert values["dist-swt"] > values["dist-rwt"] + 300
    assert values["dist-pump-pwr"] == 60
    assert all(
        values[f"zone{i}-{name}-whitewire-pwr"] == 10 for i, name in enumerate(ZONES, 1)
    )


@pytest.mark.fmu
def test_heat_house_from_store_draws_the_store_down_from_its_hot_end(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, COLD_ZONES | {"TStartPlant": 318.15})
    plant.close("v4-house-return-relay", "v5-boiler-relay")
    values = plant.run(30 * 60)
    assert values["secondary-flow"] == 0
    assert values["dist-flow"] in range(460, 511)
    assert values["store-flow"] == values["dist-flow"]
    assert plant.model.read("storeCharge") < 0
    assert values["hp-odu-pwr"] == 20
    assert values["tank1-depth1-device"] in range(4470, 4501)
    assert values["tank3-depth3-device"] < 4200
    assert values["dist-swt"] > values["dist-rwt"] + 300


@pytest.mark.fmu
def test_with_every_relay_de_energized_a_boiler_house_is_cut_off_from_the_store(
    bench: list[Bench],
) -> None:
    plant = open_bench(
        bench, COLD_ZONES | {"TStartPlant": 318.15}, scada_in_charge=False
    )
    values = plant.run(10 * 60)
    assert [values[name] for name in FLOWS] == [0, 0, 0, 0]
    assert values["hp-odu-pwr"] == 20
    assert values["dist-pump-pwr"] == 60
    assert values["tank1-depth1-device"] in range(4490, 4501)


@pytest.mark.fmu
def test_with_every_relay_de_energized_a_house_with_no_boiler_heats_from_the_store(
    bench: list[Bench],
) -> None:
    plant = open_bench(
        bench,
        COLD_ZONES | {"TStartPlant": 318.15},
        boiler=False,
        scada_in_charge=False,
    )
    values = plant.run(10 * 60)
    assert values["dist-flow"] in range(460, 511)
    assert values["store-flow"] == values["dist-flow"]
    assert values["secondary-flow"] == 0


@pytest.mark.fmu
def test_a_pump_with_nowhere_to_send_water_moves_none_and_still_draws_power(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, WARM_ZONES)
    plant.close("v1-hx-house-relay", "secondary-pump-relay", "v2-store-hot-relay")
    values = plant.run(5 * 60)
    assert values["secondary-flow"] == 0
    assert values["store-flow"] == 0
    assert values["secondary-pump-pwr"] == 60


@pytest.mark.fmu
def test_charging_through_v3_warms_the_cold_tank_and_no_other(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, WARM_ZONES)
    plant.close(*CHARGING, "v2-store-hot-relay", "v3-store-cold-relay")
    values = plant.run(30 * 60)
    assert values["store-flow"] in range(490, 511)
    assert values["tank3-depth1-device"] > 3300
    for tank in (1, 2):
        for depth in (1, 2, 3):
            assert values[f"tank{tank}-depth{depth}-device"] in range(2990, 3001)


@pytest.mark.fmu
def test_a_charge_reaches_the_store_top_first_and_stays_layered(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, WARM_ZONES)
    plant.close(*CHARGING)
    values = plant.run(15 * 60)
    down_the_store = [values[name] for name in TANK_DEPTHS]
    assert down_the_store == sorted(down_the_store, reverse=True)
    assert down_the_store[0] - down_the_store[-1] > 500


@pytest.mark.fmu
def test_the_compressor_stops_at_its_leaving_temperature_limit(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, WARM_ZONES | {"TStartPlant": 313.15})
    plant.close(*CHARGING)
    plant.run(90 * 60)
    assert max(values["hp-lwt"] for values in plant.history) in range(5490, 5511)
    running = [values["hp-odu-pwr"] > 1000 for values in plant.history]
    assert running[0] and not running[-1]
    assert plant.history[-1]["primary-flow"] == 500


@pytest.mark.fmu
def test_colder_weather_makes_the_zones_call_for_longer(bench: list[Bench]) -> None:
    def calling_share(outdoor_k: float) -> float:
        plant = open_bench(bench, {"TOutdoor": outdoor_k})
        plant.close(*CHARGING, "v4-house-return-relay", "v5-boiler-relay")
        plant.run(12 * 3600)
        calls = [values["zone1-north-whitewire-pwr"] == 10 for values in plant.history]
        assert True in calls and False in calls
        return sum(calls) / len(calls)

    assert calling_share(263.15) > calling_share(278.15) + 0.2


@pytest.mark.fmu
def test_heat_is_neither_made_nor_lost_across_every_mode(bench: list[Bench]) -> None:
    plant = open_bench(bench, COLD_ZONES)
    initial = plant.model.read("thermalEnergy")
    plant.close(*CHARGING)
    plant.run(3600 + 17)
    plant.close("v4-house-return-relay", "v5-boiler-relay")
    plant.run(3600 + 41)
    plant.open(*CHARGING)
    plant.run(3600)
    plant.close("v2-store-hot-relay", "v3-store-cold-relay")
    plant.open("v5-boiler-relay")
    plant.run(3600)
    delivered = plant.model.read("heatPumpEnergy")
    assert delivered > 15 * 3.6e6
    assert abs(plant.energy_imbalance(initial)) < 1e-6 * delivered


@pytest.mark.fmu
def test_what_the_plant_does_is_the_same_at_a_one_second_and_a_one_minute_tick(
    bench: list[Bench],
) -> None:
    def day(tick_s: int) -> dict[str, int]:
        plant = open_bench(bench, COLD_ZONES, tick_s=tick_s)
        plant.close(*CHARGING)
        plant.run(2 * 3600 + 17)
        plant.close("v4-house-return-relay", "v5-boiler-relay")
        plant.run(2 * 3600 + 41)
        plant.open(*CHARGING)
        return plant.run(2 * 3600 + 2)

    allowed_by_telemetry = {
        TelemetryName.CelsiusTimes100: 2,
        TelemetryName.GpmTimes100: 2,
        TelemetryName.PowerW: 5,
        TelemetryName.MicroVolts: 500,
        TelemetryName.MicroHz: 400_000,
    }
    fine, coarse = day(1), day(60)
    for name, telemetry in layout().telemetry_by_channel.items():
        allowed = allowed_by_telemetry[telemetry]
        assert abs(coarse[name] - fine[name]) <= allowed, name


@pytest.mark.fmu
def test_an_actuation_takes_effect_at_the_instant_it_is_stamped(
    bench: list[Bench],
) -> None:
    stepped = open_bench(bench, WARM_ZONES)
    stepped.run(30)
    stepped.close(*CHARGING)
    stepped.tick_s = 30
    at_the_minute = stepped.run(30)

    stamped = open_bench(bench, WARM_ZONES)
    stamped.now_ms = START_MS + 30_000
    stamped.close(*CHARGING)
    assert stamped.model.step(START_MS + 60_000) == at_the_minute
    assert at_the_minute["secondary-flow"] > 0


@pytest.mark.fmu
def test_a_relay_the_plant_does_not_model_moves_nothing(bench: list[Bench]) -> None:
    quiet = open_bench(bench, COLD_ZONES)
    told = open_bench(bench, COLD_ZONES)
    told.energize("vdc-relay", "zone1-north-ops-relay")
    assert told.run(600) == quiet.run(600)


@pytest.mark.fmu
def test_an_override_replaces_the_fmus_own_value(bench: list[Bench]) -> None:
    def charging(overrides: dict[str, float]) -> Bench:
        plant = open_bench(bench, WARM_ZONES | overrides)
        plant.close(*CHARGING)
        plant.run(10 * 60)
        return plant

    def approach(plant: Bench) -> int:
        values = plant.history[-1]
        return values["hp-lwt"] - values["secondary-lwt"]

    def heat_per_watt(plant: Bench) -> float:
        return plant.model.read("heatPumpHeat") / plant.history[-1]["hp-odu-pwr"]

    as_built = charging({})
    assert approach(charging({"UAExchanger": 600.0})) > approach(as_built) + 300
    tight_pipework = charging({"dpSecondaryNominal": 60e3})
    assert tight_pipework.history[-1]["secondary-flow"] in range(200, 301)
    assert heat_per_watt(charging({"TOutdoor": 283.15})) > heat_per_watt(as_built) + 0.5
    flat_cop = {
        f"COPTable[{row},{col}]": 2.0 for row in (1, 2, 3, 4) for col in (1, 2, 3)
    }
    assert 1.9 < heat_per_watt(charging(flat_cop)) < 2.0


@pytest.mark.fmu
@pytest.mark.parametrize(
    ("overrides", "message"),
    [
        ({"UAExchangr": 600.0}, "UAExchangr is not a parameter"),
        ({"v1Position": 1.0}, "v1Position is not a parameter"),
        ({"hpLwt": 300.0}, "hpLwt is not a parameter"),
    ],
    ids=["unknown", "relay-driven", "an-output"],
)
def test_an_override_of_what_cannot_be_set_is_refused_by_name(
    overrides: Mapping[str, float], message: str
) -> None:
    with pytest.raises(ValueError, match=message):
        Bench(overrides)


@pytest.mark.fmu
def test_a_channel_the_plant_has_no_value_for_is_refused_by_name() -> None:
    house0 = load_plant_layout(HAZEL_PATH)
    with pytest.raises(ValueError, match="no value for: buffer-depth1-device"):
        FmuPlantModel(
            fmu_path=FMU_PATH,
            telemetry_by_channel=house0.telemetry_by_channel,
            variable_by_channel=variable_by_channel(house0.hydronic),
            encoding_by_channel={},
            effect_by_relay={},
            overrides={},
            start_ms=START_MS,
        )


@pytest.mark.fmu
def test_a_channel_in_an_encoding_the_plant_cannot_write_is_refused_by_name() -> None:
    katahdin = layout()
    with pytest.raises(ValueError, match=r"hp-lwt is MicroVolts.*hpLwt \(K\)"):
        katahdin_model(
            fmu_path=FMU_PATH,
            layout=katahdin._replace(
                telemetry_by_channel=katahdin.telemetry_by_channel
                | {"hp-lwt": TelemetryName.MicroVolts}
            ),
            overrides={},
            start_ms=START_MS,
        )


@pytest.mark.fmu
def test_a_house_with_another_number_of_zones_is_refused() -> None:
    with pytest.raises(ValueError, match="2 zone circuits and .* models 4 zones"):
        katahdin_model(
            fmu_path=FMU_PATH,
            layout=layout(zones=("north", "south")),
            overrides={},
            start_ms=START_MS,
        )


@pytest.mark.live
@pytest.mark.fmu
def test_a_katahdin_plant_answers_its_scada_across_the_broker(tmp_path: Path) -> None:
    katahdin = layout()
    plant_alias = katahdin.g_node.alias
    assert (plant_alias, katahdin.scada_alias) == (
        f"{LARCH_ALIAS}.ta",
        f"{LARCH_ALIAS}.scada",
    )
    actuation_key = actuation_binding_key(katahdin.scada_alias, plant_alias)
    clock = [START_MS]
    model = katahdin_model(
        fmu_path=FMU_PATH, layout=katahdin, overrides=WARM_ZONES, start_ms=START_MS
    )
    plant = SimulatedPlant(
        settings=GwtaSettings(
            service_alias=plant_alias,
            g_node_path=write_g_node_json(tmp_path / "g.node.gt.json", katahdin.g_node),
        ),
        layout=katahdin,
        model=model,
        now_ms=lambda: clock[0],
    )
    url = plant.settings.rabbit.url.get_secret_value()
    provision_topology(url)
    listener = Listener(
        url,
        WrappedRoutingEnvelope(
            type_name="sim.plant.flux",
            from_alias=plant_alias,
            to_class_token=lrh(katahdin.scada_alias),
        ).routing_key,
    )

    def next_flux() -> dict[str, int]:
        plant.emit_flux()
        _, body = listener.next_body(timeout_s=5)
        _, payload = unwrap_bytes(body)
        flux = SemaCodec().from_dict(payload, expect=SimPlantFlux)
        assert flux.scada_read_time_unix_ms == clock[0]
        return dict(zip(flux.channel_name_list, flux.value_list, strict=True))

    def energize(relay: str, variable: str) -> None:
        payload = SimPlantActuation(
            relay_name=relay,
            action=ChangeRelayPin.Energize,
            actuation_time_unix_ms=clock[0],
            actual_time_utc="2026-11-11T15:00:00.000Z",
        ).to_dict()
        body = wrap_bytes(
            src=katahdin.scada_alias,
            dst=plant_alias,
            inner_type_name="sim.plant.actuation",
            inner_payload_dict=payload,
        )
        deadline = time.time() + 5
        while time.time() < deadline:
            listener.publish(actuation_key, body)
            time.sleep(0.1)
            with plant.model_lock:
                if model.read(variable) == 1.0:
                    return
        raise AssertionError(f"{relay} never reached the plant")

    plant.start()
    try:
        wait_for_consuming(plant)
        at_rest = next_flux()
        assert set(at_rest) == set(katahdin.telemetry_by_channel)
        assert at_rest["secondary-flow"] == 0
        assert at_rest["hp-odu-pwr"] == 20

        energize("v1-hx-house-relay", "v1Position")
        energize("secondary-pump-relay", "secondaryPumpOn")
        energize("hp-failsafe-relay", "hpScadaControl")
        clock[0] += 20 * 60 * 1000
        charging = next_flux()
        assert charging["secondary-flow"] in range(490, 511)
        assert charging["store-flow"] == charging["secondary-flow"]
        assert charging["tank1-depth1-device"] > at_rest["tank1-depth1-device"] + 300
        assert charging["hp-odu-pwr"] > 3000
    finally:
        plant.stop()
        listener.close()
        model.close()
