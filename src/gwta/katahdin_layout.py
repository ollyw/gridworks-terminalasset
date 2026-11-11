"""The hardware layout of a simulated Katahdin house, made from a House0
house's.

Run it with::

    uv run ta-katahdin-layout --house0 <house0-layout.json> \\
        --ltn-alias d1.isone.ct.newhaven.larch1 \\
        --zones north south east west --out <katahdin-layout.json>

The House0 layout gives the house everything the two kinds share: the
scada's own nodes, the relay board, the meters and the simulated sensors.
The pipework is replaced with a Katahdin house's: the five valves on the
board's free relays, a 0-10 V output for the secondary pump, the heat
pump's control box, three store tanks and one call circuit a zone. What a
Katahdin house has no part for (a buffer tank, a store pump, a primary
pump of the scada's) is left behind. Every id is made from the house's
alias and the name of the thing, so the same arguments give the same file.
"""

import argparse
import hashlib
import json
import uuid
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import NamedTuple, TypeVar

from gwbase.sema.enums import GwGNodeClass

from gwta.sema.base import SemaType
from gwta.sema.codec import SemaCodec
from gwta.sema.enums import (
    ActorClass,
    CirculatorRole,
    PrimaryPumpOwner,
    RefrigerantCycle,
)
from gwta.sema.property_format import LeftRightDot, SpaceheatName
from gwta.sema.types import (
    BoilerBackup,
    DataChannelGt,
    DerivedChannelGt,
    ElectricMeterChannelConfig,
    ElectricMeterComponentGt,
    GNodeGt,
    GpioRelayComponentGt,
    GpioSensorComponentGt,
    House0Layout,
    House0NoSieg,
    Hydronic,
    I2cDacOutputComponentGt,
    I2cRelayComponentGt,
    I2cThermistorReaderComponentGt,
    KatahdinLayout,
    ScadaBoardComponentGt,
    ScadaDeviceTypeGt,
    SpaceheatNodeGt,
    WaterStore,
)

House0 = House0Layout | House0NoSieg
HOUSE0_WORDS = (House0Layout, House0NoSieg)
BOARD_RESIDENTS = (
    GpioRelayComponentGt,
    GpioSensorComponentGt,
    I2cDacOutputComponentGt,
    I2cRelayComponentGt,
    I2cThermistorReaderComponentGt,
)

STORE_TANKS = 3
GALLONS_PER_TANK = 80
TEMPLATE_TANK = "tank1"

SCADA_NODES = (
    "s",
    "s2",
    "admin",
    "auto",
    "ltn",
    "la",
    "five-v-boss",
    "pico-cycler",
    "derived-generator",
    "cold-watch",
    "lc",
    "n",
    "cold-override",
    "scada-blind",
    "standby",
    "hp-boss",
    "hp-watch",
    "i2c-bus",
    "krida",
    "web-server",
    "power-meter",
)
PLANT_NODES = (
    "hp-odu",
    "secondary-pump",
    "dist-pump",
    "vdc-relay",
    "hp-scada-ops-relay",
    "secondary-pump-relay",
    "dist-010v",
    "secondary-btu",
    "secondary-flow",
    "secondary-lwt",
    "secondary-ewt",
    "dist-flow",
    "primary-flow",
    "store-flow",
    "hp-lwt",
    "hp-ewt",
    "dist-swt",
    "dist-rwt",
    "store-hot-pipe",
    "store-cold-pipe",
)
VALVE_RELAYS = (
    "v1-hx-house-relay",
    "v2-store-hot-relay",
    "v3-store-cold-relay",
    "v4-house-return-relay",
)
BOILER_VALVE_RELAY = "v5-boiler-relay"
DERIVED_CHANNELS = ("transactive-power", "last-hour-dist-energy")

Word = TypeVar("Word", bound=SemaType)


def changed(word: Word, **fields: object) -> Word:
    """The word with some fields replaced, through its own validation."""
    return type(word).model_validate(word.model_dump() | fields)


def respelled(word: Word, spellings: Mapping[str, str]) -> Word:
    """The word with every occurrence of each old spelling, in any string
    it holds, replaced by the new one: a thing named after another."""

    def respell(value: object) -> object:
        if isinstance(value, str):
            for old, new in spellings.items():
                value = value.replace(old, new)
            return value
        if isinstance(value, dict):
            return {key: respell(item) for key, item in value.items()}
        if isinstance(value, list):
            return [respell(item) for item in value]
        return value

    return type(word).model_validate(respell(word.to_dict()))


def stable_uuid(*parts: str) -> str:
    digest = hashlib.sha256("/".join(parts).encode()).digest()
    return str(uuid.UUID(bytes=digest[:16], version=4))


def spoken(name: str) -> str:
    return name.replace("-", " ").title()


class Part(NamedTuple):
    """One node of the house and the component it binds, where it binds
    one. Interior to the making of a layout."""

    node: SpaceheatNodeGt
    component: SemaType | None


class Parts:
    """The House0 house being drawn from and the Katahdin house being
    drawn up. A part is taken as it stands or under another name; a
    channel likewise."""

    def __init__(self, house0: House0) -> None:
        component_by_id = {c.component_id: c for c in house0.components}
        self.source = {
            n.name: Part(n, component_by_id[n.component_id] if n.component_id else None)
            for n in house0.sh_nodes
        }
        self.source_channel = {ch.name: ch for ch in house0.data_channels}
        self.source_derived = {d.name: d for d in house0.derived_channels}
        self.parts: dict[SpaceheatName, Part] = {}
        self.channels: dict[SpaceheatName, DataChannelGt] = {}
        self.derived: dict[SpaceheatName, DerivedChannelGt] = {}

    def take(self, name: SpaceheatName) -> None:
        self.parts[name] = self.source[name]

    def take_as(self, source: SpaceheatName, spellings: Mapping[str, str]) -> None:
        part = self.source[source]
        node = respelled(part.node, spellings)
        self.parts[node.name] = Part(
            changed(node, display_name=spoken(node.name)),
            None
            if part.component is None
            else changed(
                respelled(part.component, spellings),
                display_name=spoken(node.name),
            ),
        )

    def take_channel(self, name: SpaceheatName) -> None:
        self.channels[name] = self.source_channel[name]

    def take_channel_as(
        self, source: SpaceheatName, spellings: Mapping[str, str]
    ) -> None:
        channel = respelled(self.source_channel[source], spellings)
        self.channels[channel.name] = changed(
            channel, display_name=spoken(channel.name)
        )

    def take_derived(self, name: SpaceheatName) -> None:
        self.derived[name] = self.source_derived[name]

    def take_derived_as(
        self, source: SpaceheatName, spellings: Mapping[str, str]
    ) -> None:
        derived = respelled(self.source_derived[source], spellings)
        self.derived[derived.name] = changed(derived, display_name=spoken(derived.name))

    def channels_captured_by(self, node: SpaceheatName) -> list[SpaceheatName]:
        return [
            ch.name
            for ch in self.source_channel.values()
            if ch.captured_by_node_name == node
        ]


def free_relay_names(house0: House0, parts: Parts) -> list[str]:
    """The relays of the house's board that no part taken so far is on, in
    the board's own order."""
    boards = [c for c in house0.components if isinstance(c, ScadaBoardComponentGt)]
    if len(boards) != 1:
        raise ValueError(f"the House0 layout has {len(boards)} boards, expected one")
    records = [
        r
        for r in house0.device_types
        if isinstance(r, ScadaDeviceTypeGt) and r.device_type == boards[0].device_type
    ]
    if len(records) != 1:
        raise ValueError(
            f"the House0 layout has {len(records)} records of its board's "
            f"device type {boards[0].device_type}, expected one"
        )
    taken = {
        part.component.relay_name
        for part in parts.parts.values()
        if isinstance(part.component, I2cRelayComponentGt)
    }
    return [r.relay_name for r in records[0].i2c_relays if r.relay_name not in taken]


def katahdin_layout(
    house0: House0,
    *,
    ltn_alias: LeftRightDot,
    zones: Sequence[SpaceheatName],
    boiler: bool,
) -> KatahdinLayout:
    """A Katahdin house with these zones, one call circuit each, under
    this LeafTransactiveNode alias. With `boiler` it keeps the House0
    house's boiler backup and has the boiler's valve; without, it has no
    backup."""
    if not zones:
        raise ValueError("a house needs a zone")
    if boiler and not isinstance(house0.hydronic.backup, BoilerBackup):
        raise ValueError("the House0 layout has no boiler backup to keep")
    ta_alias = f"{ltn_alias}.ta"
    house = ltn_alias.rsplit(".", 1)[-1]
    parts = Parts(house0)

    for name in SCADA_NODES + PLANT_NODES:
        parts.take(name)
        for channel in parts.channels_captured_by(name):
            if parts.source_channel[channel].about_node_name in SCADA_NODES + (
                PLANT_NODES
            ):
                parts.take_channel(channel)
    for name in DERIVED_CHANNELS:
        parts.take_derived(name)
    # The control box stands on the outdoor unit's simulated device: the
    # simulated device types have none for a control box, and one that does
    # (a SimHpCtrlBox beside SimHpOdu) retires the borrowing.
    parts.take_as("hp-odu", {"hp-odu": "hp-ctrl-box"})
    parts.take_channel_as("hp-odu-pwr", {"hp-odu": "hp-ctrl-box"})
    ctrl_box = parts.parts["hp-ctrl-box"]
    parts.parts["hp-ctrl-box"] = Part(
        changed(ctrl_box.node, nameplate_power_w=None), ctrl_box.component
    )

    circulators = {c.role: c for c in house0.hydronic.circulators}
    for role in (CirculatorRole.Dist, CirculatorRole.Secondary):
        parts.take_derived(circulators[role].running_channel_name)
    store_output = circulators[CirculatorRole.Store].zero_ten_node_name
    if store_output is None:
        raise ValueError("the House0 layout's store pump has no 0-10 V output")
    parts.take_as(store_output, {store_output: "secondary-010v"})
    parts.take_channel_as(store_output, {store_output: "secondary-010v"})

    backup = house0.hydronic.backup if boiler else None
    if isinstance(backup, BoilerBackup):
        parts.take("backup")
        for name in (backup.failsafe_relay_name, backup.aquastat_ctrl_relay_name):
            parts.take(name)
            parts.take_channel(name)

    for tank in range(1, STORE_TANKS + 1):
        spellings = {
            TEMPLATE_TANK: f"tank{tank}",
            spoken(TEMPLATE_TANK): spoken(f"tank{tank}"),
        }
        parts.take_as(TEMPLATE_TANK, spellings)
        for channel in parts.channels_captured_by(TEMPLATE_TANK):
            depth = parts.source_channel[channel].about_node_name
            parts.take_as(depth, spellings)
            parts.take_channel_as(channel, spellings)
            parts.take_derived_as(depth, spellings)

    circuit = house0.hydronic.zone_call_circuits[0]
    zone = house0.hydronic.zones[0]
    if circuit.temp_channel_name is None or circuit.setpoint_channel_name is None:
        raise ValueError("the House0 layout's first circuit senses no temperature")
    template = circuit.ops_relay_node.removesuffix("-ops-relay")
    whitewire = parts.source_channel[circuit.whitewire_channel_name]
    temp = parts.source_channel[circuit.temp_channel_name]
    heat_call = next(
        d.name
        for d in house0.derived_channels
        if d.strategy == "heat-call"
        and d.input_channel_names == [circuit.whitewire_channel_name]
    )
    relays = iter(free_relay_names(house0, parts))
    valve_relays = VALVE_RELAYS + ((BOILER_VALVE_RELAY,) if boiler else ())
    for valve_relay in valve_relays:
        parts.take_as(circuit.ops_relay_node, {circuit.ops_relay_node: valve_relay})
        parts.take_channel_as(
            circuit.ops_relay_node, {circuit.ops_relay_node: valve_relay}
        )
    circuits = []
    for position, name in enumerate(zones, start=1):
        spellings = {template: f"zone{position}-{name}"}
        for node in (
            whitewire.about_node_name,
            temp.about_node_name,
            temp.captured_by_node_name,
            circuit.failsafe_relay_node,
            circuit.ops_relay_node,
        ):
            parts.take_as(node, spellings)
        for channel in (
            whitewire.name,
            temp.name,
            circuit.failsafe_relay_node,
            circuit.ops_relay_node,
        ):
            parts.take_channel_as(channel, spellings)
        for derived in (heat_call, circuit.setpoint_channel_name):
            parts.take_derived_as(derived, spellings)
        circuits.append(
            changed(
                respelled(circuit, spellings),
                circuit_position=position,
                name=name,
                serves_zone=name,
            )
        )
    for name, part in parts.parts.items():
        if isinstance(part.component, I2cRelayComponentGt) and name not in parts.source:
            parts.parts[name] = Part(
                part.node, changed(part.component, relay_name=next(relays))
            )

    board_id = next(
        stable_uuid(house, "component", name)
        for name, part in parts.parts.items()
        if isinstance(part.component, ScadaBoardComponentGt)
    )
    nodes = []
    components = []
    for name, part in parts.parts.items():
        component_id = (
            None if part.component is None else stable_uuid(house, "component", name)
        )
        nodes.append(
            changed(
                part.node,
                sh_node_id=stable_uuid(house, "node", name),
                component_id=component_id,
                display_name=f"{spoken(house)} Main Scada"
                if part.node.actor_class == ActorClass.PrimaryScada
                else part.node.display_name,
            )
        )
        component = part.component
        if component is None:
            continue
        if isinstance(component, ElectricMeterComponentGt):
            component = changed(
                component,
                config_list=[
                    ElectricMeterChannelConfig(channel_name=ch.name)
                    for ch in parts.channels.values()
                    if ch.captured_by_node_name == name
                ],
            )
        if isinstance(component, BOARD_RESIDENTS):
            component = changed(component, board_component_id=board_id)
        components.append(changed(component, component_id=component_id))

    return KatahdinLayout(
        g_nodes=[
            GNodeGt(
                g_node_id=stable_uuid(house, "g-node", g.g_node_class),
                alias=ltn_alias
                if g.g_node_class == GwGNodeClass.LeafTransactiveNode.value
                else f"{ltn_alias}.{g.alias.rsplit('.', 1)[-1]}",
                base_class=g.base_class,
                g_node_class=g.g_node_class,
                status=g.status,
                position_point_id=None
                if g.position_point_id is None
                else stable_uuid(house, "position-point", g.g_node_class),
                display_name=f"{spoken(house)} Heating System {g.g_node_class}",
            )
            for g in house0.g_nodes
        ],
        sh_nodes=nodes,
        data_channels=[
            changed(
                ch,
                id=stable_uuid(house, "channel", ch.name),
                terminal_asset_alias=ta_alias,
            )
            for ch in parts.channels.values()
        ],
        derived_channels=[
            changed(
                d,
                id=stable_uuid(house, "channel", d.name),
                terminal_asset_alias=ta_alias,
            )
            for d in parts.derived.values()
        ],
        components=components,
        device_types=list(house0.device_types),
        hydronic=Hydronic(
            zones=[
                changed(zone, name=name, primary_circuit_position=position)
                for position, name in enumerate(zones, start=1)
            ],
            zone_call_circuits=circuits,
            circulators=[
                circulators[CirculatorRole.Dist],
                changed(
                    circulators[CirculatorRole.Secondary],
                    zero_ten_node_name="secondary-010v",
                ),
            ],
            water_store=WaterStore(
                total_store_tanks=STORE_TANKS,
                gallons_per_tank=GALLONS_PER_TANK,
                temp_sensors_per_tank=3,
            ),
            backup=backup,
            primary_flow_source=house0.hydronic.primary_flow_source,
            primary_pump_owner=PrimaryPumpOwner.HeatPump,
            refrigerant_cycle=RefrigerantCycle.Single,
        ),
        disabled_node_names=[],
        disabled_channel_names=[],
    )


def load_house0(path: Path) -> House0:
    decoded = SemaCodec().from_dict(json.loads(path.read_text()))
    if not isinstance(decoded, HOUSE0_WORDS):
        raise ValueError(
            f"{path} holds a {type(decoded).__name__}, and a Katahdin house is "
            f"made from a {' or a '.join(word.__name__ for word in HOUSE0_WORDS)}"
        )
    return decoded


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--house0", type=Path, required=True, help="the House0 layout to draw from"
    )
    parser.add_argument(
        "--ltn-alias",
        required=True,
        help="the house's LeafTransactiveNode alias; its terminal asset and "
        "scada take .ta and .scada under it",
    )
    parser.add_argument(
        "--zones", nargs="+", required=True, help="the zones, in circuit order"
    )
    parser.add_argument(
        "--no-boiler",
        action="store_true",
        help="a house with no backup, and so no boiler valve",
    )
    parser.add_argument(
        "--out", type=Path, required=True, help="where the layout is written"
    )
    args = parser.parse_args()
    layout = katahdin_layout(
        load_house0(args.house0),
        ltn_alias=args.ltn_alias,
        zones=args.zones,
        boiler=not args.no_boiler,
    )
    args.out.write_text(json.dumps(layout.to_dict(), indent=2) + "\n")


if __name__ == "__main__":
    main()
