"""The Katahdin plant: a monobloc heat pump on a glycol loop, a plate
exchanger, a three-tank store and a zoned distribution loop, with an oil
boiler or immersion elements as backup. Its physics is the FMU generated
from modelica/Katahdin.mo; this module says which of the FMU's outputs each
channel of a Katahdin house reads and which of its inputs each relay
drives.
"""

from collections.abc import Mapping
from pathlib import Path
from typing import NamedTuple

from fmpy import read_model_description

from gwta.fmu_model import FmuPlantModel, RelayEffect
from gwta.sensing import device_encodings
from gwta.plant_layout import PlantLayout
from gwta.sema.enums import RelayClosedOrOpen
from gwta.sema.property_format import SpaceheatName, UTCMilliseconds
from gwta.sema.types import BoilerBackup, Hydronic

VARIABLE_BY_PLANT_CHANNEL: dict[SpaceheatName, str] = {
    "hp-lwt": "hpLwt",
    "hp-ewt": "hpEwt",
    "secondary-lwt": "secondaryLwt",
    "secondary-ewt": "secondaryEwt",
    "dist-swt": "distSwt",
    "dist-rwt": "distRwt",
    "store-hot-pipe": "storeHotPipe",
    "store-cold-pipe": "storeColdPipe",
    "hp-odu-pwr": "hpOduPower",
    "hp-ctrl-box-pwr": "hpCtrlBoxPower",
    "dist-pump-pwr": "distPumpPower",
    "secondary-pump-pwr": "secondaryPumpPower",
}

VARIABLE_BY_FLOW_CHANNEL: dict[SpaceheatName, str] = {
    "primary-flow": "primaryFlow",
    "secondary-flow": "secondaryFlow",
    "dist-flow": "distFlow",
    "store-flow": "storeFlow",
}


class ContactEffect(NamedTuple):
    """What one relay's contact does to the plant: the FMU input it drives
    and the value that input takes with the contact closed and open."""

    variable: str
    closed: float
    open: float


OPEN_WHEN_POWERED = (1.0, 0.0)
CLOSED_WHEN_POWERED = (0.0, 1.0)


def variable_by_channel(hydronic: Hydronic) -> dict[SpaceheatName, str]:
    """The FMU output behind every channel a Katahdin house can show. Tank 1
    is the hot tank and tank 3 the cold one; depth 1 is the top of a tank.
    The zone at circuit position i is the model's zone i. A flow is also
    behind its meter's pulse rate (`-hz`), and a tank depth behind its
    module's temperature (`-device`) and thermistor voltage (`-micro-v`)."""
    variables = dict(VARIABLE_BY_PLANT_CHANNEL)
    for flow, variable in VARIABLE_BY_FLOW_CHANNEL.items():
        variables[flow] = variables[f"{flow}-hz"] = variable
    store = hydronic.water_store
    if store is not None:
        for tank in range(1, store.total_store_tanks + 1):
            for depth in range(1, store.temp_sensors_per_tank + 1):
                for suffix in ("", "-device", "-micro-v"):
                    variables[f"tank{tank}-depth{depth}{suffix}"] = (
                        f"tankDepth[{tank},{depth}]"
                    )
    for circuit in hydronic.zone_call_circuits:
        zone = circuit.circuit_position
        variables[circuit.whitewire_channel_name] = f"zoneCallPower[{zone}]"
        if circuit.temp_channel_name is not None:
            variables[circuit.temp_channel_name] = f"zoneTemperature[{zone}]"
    return variables


def contact_effects(hydronic: Hydronic) -> dict[SpaceheatName, ContactEffect]:
    """What a closed contact does, for each relay of a Katahdin house that
    switches something the model has. A valve's relay feeds its motor, and
    with no feed a valve rests where the house's failsafe needs it: the
    boiler heats a house that has one, with the store valved off from the
    house, and the store heats a house that has none. Hand-kept: no word
    says what a valve does when it is fed, and one that does retires
    this table."""
    has_boiler = isinstance(hydronic.backup, BoilerBackup)
    effects = {
        "v1-hx-house-relay": ContactEffect("v1Position", *OPEN_WHEN_POWERED),
        "v2-store-hot-relay": ContactEffect("v2Position", *CLOSED_WHEN_POWERED),
        "v3-store-cold-relay": ContactEffect("v3Position", *OPEN_WHEN_POWERED),
        "v4-house-return-relay": ContactEffect(
            "v4Position",
            *(OPEN_WHEN_POWERED if has_boiler else CLOSED_WHEN_POWERED),
        ),
        "secondary-pump-relay": ContactEffect("secondaryPumpOn", 1.0, 0.0),
        "hp-scada-ops-relay": ContactEffect("hpEnable", 1.0, 0.0),
    }
    if has_boiler:
        effects["v5-boiler-relay"] = ContactEffect("v5Position", *CLOSED_WHEN_POWERED)
    return effects


def effect_by_relay(layout: PlantLayout) -> dict[SpaceheatName, RelayEffect]:
    """What each relay of a Katahdin house drives. Which of a relay's two
    positions closes its contact is the layout's to say, and a layout that
    does not say it for a relay the model needs is refused. In a house
    with a boiler the scada's call reaches the heat pump only while the
    boiler's failsafe relay is energized."""
    effects: dict[SpaceheatName, RelayEffect] = {}
    for relay, contact in contact_effects(layout.hydronic).items():
        config = layout.config_by_relay.get(relay)
        states = (
            None
            if config is None
            else {config.energized_state, config.de_energized_state}
        )
        if config is None or states != set(RelayClosedOrOpen.values()):
            raise ValueError(
                f"the layout does not say which position of {relay} closes its contact"
            )
        closes_when_energized = (
            config.energized_state == RelayClosedOrOpen.RelayClosed.value
        )
        effects[relay] = RelayEffect(
            contact.variable,
            energized=contact.closed if closes_when_energized else contact.open,
            de_energized=contact.open if closes_when_energized else contact.closed,
        )
    backup = layout.hydronic.backup
    if isinstance(backup, BoilerBackup):
        effects[backup.failsafe_relay_name] = RelayEffect("hpScadaControl", 1.0, 0.0)
    return effects


def katahdin_model(
    *,
    fmu_path: Path,
    layout: PlantLayout,
    overrides: Mapping[str, float],
    start_ms: UTCMilliseconds,
) -> FmuPlantModel:
    """A Katahdin plant for one house, refused if the house has more or
    fewer zones than the FMU was generated with."""
    zones = len(layout.hydronic.zone_call_circuits)
    fmu_zones = sum(
        1
        for variable in read_model_description(str(fmu_path)).modelVariables
        if variable.name.startswith("zoneTemperature[")
    )
    if zones != fmu_zones:
        raise ValueError(
            f"the layout has {zones} zone circuits and {fmu_path.name} models "
            f"{fmu_zones} zones"
        )
    return FmuPlantModel(
        fmu_path=fmu_path,
        telemetry_by_channel=layout.telemetry_by_channel,
        variable_by_channel=variable_by_channel(layout.hydronic),
        encoding_by_channel=device_encodings(layout),
        effect_by_relay=effect_by_relay(layout),
        overrides=overrides,
        start_ms=start_ms,
    )
