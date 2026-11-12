"""The House0 plant, driven as a scada drives it: relays in, channel
readings out. The house is a simulated Beech: a House0 layout whose every
sensing device is simulated, with Beech's two zones and three store
tanks."""

from collections.abc import Iterator, Mapping
from pathlib import Path

import pytest

from gwta.fmu_model import RelayEffect
from gwta.house0 import effect_by_relay, house0_model, variable_by_channel
from gwta.plant import fmu_model
from gwta.plant_layout import PlantLayout, load_layout, load_plant_layout, plant_layout
from gwta.sema.enums import ChangeRelayPin
from gwta.sema.types import RelayControlConfig, SimPlantActuation

FMU_PATH = Path(__file__).parent.parent / "build" / "BeechPlant.fmu"
CONFIG = Path(__file__).parent / "config"
BEECH_PATH = CONFIG / "gw.house0.beech.layout.json"
ORANGE_PATH = CONFIG / "gw.house0.orange.layout.json"
HAZEL_PATH = CONFIG / "gw.house0.no.sieg.hazel.layout.json"
START_MS = 1_794_300_000_000

HELD_BY_SCADA = (
    "hp-failsafe-relay",
    "aquastat-ctrl-relay",
    "primary-pump-failsafe-relay",
    "zone1-down-failsafe-relay",
    "zone2-up-failsafe-relay",
)
SIEG_TRAVEL_S = 94

WARM_ZONES = {"TStartZone": 295.15}
COLD_ZONES = {"TStartZone": 291.15}


def layout() -> PlantLayout:
    return load_plant_layout(BEECH_PATH)


class Bench:
    """One plant and the clock it is stepped by. A scada in charge holds
    every call itself and makes none, with the Siegenthaler valve held
    where the plant starts it, keeping all; with none in charge every relay
    is de-energized."""

    def __init__(
        self,
        overrides: Mapping[str, float],
        tick_s: int = 60,
        scada_in_charge: bool = True,
    ) -> None:
        if not FMU_PATH.exists():
            pytest.fail(f"{FMU_PATH} is missing: run scripts/build_fmu.sh")
        self.layout = layout()
        self.model = house0_model(
            fmu_path=FMU_PATH,
            layout=self.layout,
            overrides=overrides,
            start_ms=START_MS,
        )
        self.now_ms = START_MS
        self.tick_s = tick_s
        self.history: list[dict[str, int]] = []
        if scada_in_charge:
            for relay in HELD_BY_SCADA:
                self.put(relay, "Scada")
            self.put("hp-scada-ops-relay", "RelayOpen")
            self.put("hp-loop-on-off-relay", "RelayOpen")

    def put(self, relay: str, state: str) -> None:
        """Bring a relay to the state the layout gives that name."""
        config = self.layout.config_by_relay[relay]
        action = {
            config.energized_state: ChangeRelayPin.Energize,
            config.de_energized_state: ChangeRelayPin.DeEnergize,
        }[state]
        self.model.actuate(
            SimPlantActuation(
                relay_name=relay,
                action=action,
                actuation_time_unix_ms=self.now_ms,
                actual_time_utc="2026-11-11T15:00:00.000Z",
            )
        )

    def call_heat_pump(self) -> None:
        self.put("hp-scada-ops-relay", "RelayClosed")
        self.put("primary-pump-scada-ops-relay", "RelayClosed")

    def drive_sieg(self, toward: str) -> dict[str, int]:
        """Run the Siegenthaler valve to one of its stops and hold it."""
        self.put("hp-loop-keep-send-relay", toward)
        self.put("hp-loop-on-off-relay", "RelayClosed")
        values = self.run(SIEG_TRAVEL_S + 6)
        self.put("hp-loop-on-off-relay", "RelayOpen")
        return values

    def run(self, seconds: int) -> dict[str, int]:
        end_ms = self.now_ms + seconds * 1000
        while self.now_ms < end_ms:
            self.now_ms = min(self.now_ms + self.tick_s * 1000, end_ms)
            self.history.append(self.model.step(self.now_ms))
        return self.history[-1]

    def energy_imbalance(self, initial_energy: float) -> float:
        return (self.model.read("thermalEnergy") - initial_energy) - (
            self.model.read("heatPumpEnergy")
            + self.model.read("boilerEnergy")
            - self.model.read("lossEnergy")
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
    tick_s: int = 60,
    scada_in_charge: bool = True,
) -> Bench:
    opened.append(Bench(overrides, tick_s, scada_in_charge))
    return opened[-1]


def test_every_channel_of_the_house_reads_an_fmu_output() -> None:
    variables = variable_by_channel(layout().hydronic)
    assert variables["hp-lwt"] == "hpLwt"
    assert variables["sieg-flow"] == "siegFlow"
    assert variables["sieg-flow-hz"] == "siegFlow"
    assert variables["buffer-depth2-device"] == "bufferDepth[2]"
    assert variables["buffer-depth3-micro-v"] == "bufferDepth[3]"
    assert variables["tank1-depth1-device"] == "tankDepth[1,1]"
    assert variables["tank3-depth3-micro-v"] == "tankDepth[3,3]"
    assert variables["zone2-up-whitewire-pwr"] == "zoneCallPower[2]"
    assert variables["zone1-down-temp"] == "zoneTemperature[1]"
    assert set(layout().telemetry_by_channel) <= set(variables)


def test_relays_rest_with_the_boiler_heating_the_house() -> None:
    effects = effect_by_relay(layout())
    resting = {
        relay: (effect.variable, effect.de_energized)
        for relay, effect in effects.items()
    }
    assert resting == {
        "hp-failsafe-relay": ("hpScadaControl", 0.0),
        "hp-scada-ops-relay": ("hpEnable", 1.0),
        "aquastat-ctrl-relay": ("boilerScadaControl", 0.0),
        "primary-pump-failsafe-relay": ("primaryPumpScadaControl", 0.0),
        "primary-pump-scada-ops-relay": ("primaryPumpOn", 0.0),
        "hp-loop-on-off-relay": ("siegMotorOn", 1.0),
        "hp-loop-keep-send-relay": ("siegTowardKeep", 0.0),
        "charge-discharge-relay": ("chargeDischarge", 0.0),
        "store-pump-relay": ("storePumpOn", 0.0),
        "zone1-down-failsafe-relay": ("zoneScadaControl[1]", 0.0),
        "zone1-down-ops-relay": ("zoneScadaCall[1]", 0.0),
        "zone2-up-failsafe-relay": ("zoneScadaControl[2]", 0.0),
        "zone2-up-ops-relay": ("zoneScadaCall[2]", 0.0),
    }
    assert set(layout().relay_names) - set(effects) == {
        "vdc-relay",
        "tstat-common-relay",
    }
    for effect in effects.values():
        assert {effect.energized, effect.de_energized} == {0.0, 1.0}


def rewired(config: RelayControlConfig, **fields: str) -> RelayControlConfig:
    return RelayControlConfig.model_validate(config.model_dump() | fields)


def test_a_relay_is_in_the_state_the_layout_gives_its_position() -> None:
    house = layout()
    valve = house.config_by_relay["charge-discharge-relay"]
    assert valve.energized_state == "ChargingStore"
    swapped = house._replace(
        config_by_relay=house.config_by_relay
        | {
            "charge-discharge-relay": rewired(
                valve,
                energized_state=valve.de_energized_state,
                de_energized_state=valve.energized_state,
            )
        }
    )
    assert effect_by_relay(house)["charge-discharge-relay"] == RelayEffect(
        "chargeDischarge", energized=1.0, de_energized=0.0
    )
    assert effect_by_relay(swapped)["charge-discharge-relay"] == RelayEffect(
        "chargeDischarge", energized=0.0, de_energized=1.0
    )


@pytest.mark.parametrize(
    ("relay", "states"),
    [
        ("store-pump-relay", "RelayClosed and which RelayOpen"),
        ("hp-loop-keep-send-relay", "SendLess and which SendMore"),
    ],
)
def test_a_relay_whose_states_the_layout_does_not_give_is_refused(
    relay: str, states: str
) -> None:
    house = layout()
    failsafe = house.config_by_relay["hp-failsafe-relay"]
    message = f"does not say which of {relay}'s positions is {states}"
    for configs in (
        {name: c for name, c in house.config_by_relay.items() if name != relay},
        house.config_by_relay | {relay: failsafe},
    ):
        with pytest.raises(ValueError, match=message):
            effect_by_relay(house._replace(config_by_relay=configs))


def test_a_house_with_no_siegenthaler_loop_has_no_fmu() -> None:
    word = load_layout(HAZEL_PATH)
    with pytest.raises(ValueError, match="no FMU is the plant of a House0NoSieg"):
        fmu_model(
            word,
            fmu_path=FMU_PATH,
            layout=plant_layout(word),
            overrides={},
            start_ms=START_MS,
        )


@pytest.mark.fmu
def test_a_house_of_another_size_is_refused() -> None:
    with pytest.raises(
        ValueError,
        match="1 zone circuits and 1 store tanks, and BeechPlant.fmu models "
        "2 zones and 3 tanks",
    ):
        house0_model(
            fmu_path=FMU_PATH,
            layout=load_plant_layout(ORANGE_PATH),
            overrides={},
            start_ms=START_MS,
        )


@pytest.mark.fmu
def test_a_house0_layout_is_run_from_the_fmu_it_is_given() -> None:
    word = load_layout(BEECH_PATH)
    model = fmu_model(
        word,
        fmu_path=FMU_PATH,
        layout=plant_layout(word),
        overrides={},
        start_ms=START_MS,
    )
    try:
        assert set(model.step(START_MS + 5000)) == set(layout().telemetry_by_channel)
    finally:
        model.close()


@pytest.mark.fmu
def test_a_plant_at_rest_reports_every_channel_and_moves_no_water(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, WARM_ZONES)
    values = plant.run(30 * 60)
    assert set(values) == set(plant.layout.telemetry_by_channel)
    for flow in ("primary-flow", "sieg-flow", "dist-flow", "store-flow"):
        assert values[flow] == 0
        assert values[f"{flow}-hz"] == 0
    assert values["hp-odu-pwr"] == 20
    assert values["hp-idu-pwr"] == 10
    assert values["primary-pump-pwr"] == values["store-pump-pwr"] == 0
    assert values["zone1-down-whitewire-pwr"] == values["zone2-up-whitewire-pwr"] == 0
    assert 2700 < values["hp-lwt"] < 3020


@pytest.mark.fmu
def test_with_no_scada_the_boiler_heats_the_house_and_the_valve_goes_to_send(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, COLD_ZONES, scada_in_charge=False)
    assert plant.model.read("siegKeep") == 1.0
    start = plant.run(5)
    values = plant.run(2 * 3600)
    assert plant.model.read("siegKeep") == 0.0
    assert plant.model.read("boilerEnergy") > 20e6
    assert plant.model.read("heatPumpEnergy") == 0.0
    assert values["primary-flow"] == 0
    assert values["buffer-depth2-device"] > start["buffer-depth2-device"] + 1000
    assert values["zone1-down-whitewire-pwr"] == values["zone2-up-whitewire-pwr"] == 10
    assert values["dist-flow"] > 300
    assert values["dist-swt"] > start["dist-swt"] + 1000
    assert values["zone1-down-temp"] > start["zone1-down-temp"]


@pytest.mark.fmu
def test_the_boiler_stops_once_the_buffer_is_at_its_aquastat_setting(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, WARM_ZONES, scada_in_charge=False)
    plant.run(4 * 3600)
    fired = plant.model.read("boilerEnergy")
    assert fired > 0
    assert plant.model.read("bufferDepth[2]") > 322.15 - 8
    plant.put("aquastat-ctrl-relay", "Scada")
    plant.run(3600)
    assert plant.model.read("boilerEnergy") == fired
    assert plant.model.read("oilBoilerPower") == 0.0


@pytest.mark.fmu
def test_a_called_heat_pump_heats_the_water_its_pump_moves(bench: list[Bench]) -> None:
    plant = open_bench(bench, WARM_ZONES)
    plant.drive_sieg("SendMore")
    plant.put("hp-scada-ops-relay", "RelayClosed")
    stalled = plant.run(10 * 60)
    assert stalled["primary-flow"] == 0
    assert stalled["hp-odu-pwr"] == 20
    plant.put("primary-pump-scada-ops-relay", "RelayClosed")
    values = plant.run(20 * 60)
    assert values["primary-flow"] > 300
    assert values["primary-flow-hz"] > 50_000_000
    assert values["primary-pump-pwr"] > 0
    assert values["hp-odu-pwr"] > 1000
    assert values["hp-idu-pwr"] > 500
    assert values["hp-lwt"] > values["hp-ewt"] + 200
    plant.put("hp-scada-ops-relay", "RelayOpen")
    assert plant.run(5 * 60)["hp-odu-pwr"] == 20


@pytest.mark.fmu
def test_the_heat_pump_runs_its_own_primary_pump_when_the_scada_hands_it_over(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, WARM_ZONES)
    plant.drive_sieg("SendMore")
    plant.put("primary-pump-failsafe-relay", "HeatPump")
    assert plant.run(5 * 60)["primary-flow"] == 0
    plant.put("hp-scada-ops-relay", "RelayClosed")
    values = plant.run(10 * 60)
    assert values["primary-flow"] > 300
    assert values["hp-odu-pwr"] > 1000
    plant.put("hp-scada-ops-relay", "RelayOpen")
    assert plant.run(5 * 60)["primary-flow"] == 0


@pytest.mark.fmu
def test_the_heat_pumps_call_does_not_reach_it_while_its_aquastat_holds_it(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, WARM_ZONES)
    plant.put("hp-failsafe-relay", "BufferTankAquastat")
    plant.call_heat_pump()
    values = plant.run(10 * 60)
    assert values["primary-flow"] > 300
    assert values["hp-odu-pwr"] == 20


@pytest.mark.fmu
def test_the_siegenthaler_valve_keeps_or_sends_what_the_heat_pump_makes(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, WARM_ZONES, tick_s=5)
    plant.call_heat_pump()
    kept = plant.run(10 * 60)
    assert plant.model.read("siegKeep") == 1.0
    assert kept["sieg-flow"] == pytest.approx(kept["primary-flow"], abs=3)
    assert kept["sieg-hot"] > kept["buffer-hot-pipe"] + 500
    buffer_before = kept["buffer-depth1-device"]

    part_way = 60
    plant.put("hp-loop-keep-send-relay", "SendMore")
    plant.put("hp-loop-on-off-relay", "RelayClosed")
    plant.run(part_way)
    plant.put("hp-loop-on-off-relay", "RelayOpen")
    held = plant.model.read("siegKeep")
    assert 0.0 < held < 1.0
    plant.run(60)
    assert plant.model.read("siegKeep") == pytest.approx(held, abs=1e-3)

    sent = plant.drive_sieg("SendMore")
    assert plant.model.read("siegKeep") == 0.0
    assert sent["sieg-flow"] == 0
    sent = plant.run(20 * 60)
    assert sent["primary-flow"] > 300
    assert sent["buffer-depth1-device"] > buffer_before + 500

    plant.drive_sieg("SendLess")
    assert plant.model.read("siegKeep") == 1.0


@pytest.mark.fmu
def test_the_store_charges_from_the_heat_pump_and_discharges_to_the_house(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, COLD_ZONES)
    plant.put("charge-discharge-relay", "ChargingStore")
    plant.call_heat_pump()
    plant.drive_sieg("SendMore")
    start = plant.history[-1]
    charged = plant.run(2 * 3600)
    assert plant.model.read("storeCharge") > 2e-4
    assert charged["store-flow"] == 0
    assert charged["tank1-depth1-device"] > start["tank1-depth1-device"] + 1000
    assert charged["store-hot-pipe"] > charged["store-cold-pipe"]
    assert charged["buffer-depth1-device"] <= start["buffer-depth1-device"] + 100

    plant.put("hp-scada-ops-relay", "RelayOpen")
    plant.put("primary-pump-scada-ops-relay", "RelayOpen")
    plant.put("charge-discharge-relay", "DischargingStore")
    plant.put("store-pump-relay", "RelayClosed")
    for zone in ("zone1-down", "zone2-up"):
        plant.put(f"{zone}-ops-relay", "RelayClosed")
    discharged = plant.run(30 * 60)
    assert discharged["store-flow"] > 200
    assert discharged["store-pump-pwr"] > 0
    assert plant.model.read("storeCharge") < -1e-4
    assert discharged["dist-flow"] > 300
    assert discharged["buffer-depth1-device"] > charged["buffer-depth1-device"] + 500
    assert discharged["tank1-depth1-device"] < charged["tank1-depth1-device"]


@pytest.mark.fmu
def test_a_zone_the_scada_holds_calls_only_when_the_scada_calls_it(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, COLD_ZONES)
    held = plant.run(10 * 60)
    assert held["zone1-down-whitewire-pwr"] == held["zone2-up-whitewire-pwr"] == 0
    assert held["dist-flow"] == 0
    assert held["dist-pump-pwr"] == 0
    plant.put("zone2-up-ops-relay", "RelayClosed")
    called = plant.run(10 * 60)
    assert called["zone1-down-whitewire-pwr"] == 0
    assert called["zone2-up-whitewire-pwr"] == 10
    assert called["dist-flow"] > 100
    assert called["dist-pump-pwr"] > 0
    plant.put("zone2-up-failsafe-relay", "WallThermostat")
    plant.put("zone2-up-ops-relay", "RelayOpen")
    assert plant.run(10 * 60)["zone2-up-whitewire-pwr"] == 10


@pytest.mark.fmu
def test_heat_is_neither_made_nor_lost_but_by_the_heat_pump_the_boiler_and_the_losses(
    bench: list[Bench],
) -> None:
    plant = open_bench(bench, COLD_ZONES, scada_in_charge=False)
    initial = plant.model.read("thermalEnergy")
    plant.run(3600)
    for relay in HELD_BY_SCADA:
        plant.put(relay, "Scada")
    plant.put("charge-discharge-relay", "ChargingStore")
    plant.put("primary-pump-scada-ops-relay", "RelayClosed")
    plant.run(2 * 3600)
    plant.put("zone1-down-ops-relay", "RelayClosed")
    plant.put("charge-discharge-relay", "DischargingStore")
    plant.put("store-pump-relay", "RelayClosed")
    plant.run(3600)
    assert plant.model.read("boilerEnergy") > 1e6
    assert plant.model.read("heatPumpEnergy") > 1e6
    assert abs(plant.energy_imbalance(initial)) < 1e4
