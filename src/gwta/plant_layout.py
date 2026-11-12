"""What a simulated plant reads from its house's hardware layout."""

import json
from pathlib import Path
from typing import NamedTuple

from gwbase.sema.enums import GwGNodeClass

from gwta.sema.codec import SemaCodec
from gwta.sema.enums import ActorClass, SimDeviceType, TelemetryName
from gwta.sema.property_format import LeftRightDot, SpaceheatName
from gwta.sema.types import (
    ElectricMeterComponentGt,
    GNodeGt,
    GpioRelayComponentGt,
    House0Layout,
    House0NoSieg,
    Hydronic,
    I2cRelayComponentGt,
    KatahdinLayout,
    RelayControlConfig,
    SimPicoBtuMeterComponentGt,
    SimPicoFlowModuleComponentGt,
    SimPicoTankModuleComponentGt,
    SimSensorComponentGt,
)

# The layout words a plant reads: one House0 house, with a Siegenthaler loop
# or without, or one Katahdin house.
Layout = House0Layout | House0NoSieg | KatahdinLayout
LAYOUT_WORDS = (House0Layout, House0NoSieg, KatahdinLayout)

SensingComponent = (
    ElectricMeterComponentGt
    | SimPicoBtuMeterComponentGt
    | SimPicoFlowModuleComponentGt
    | SimPicoTankModuleComponentGt
    | SimSensorComponentGt
)
SENSING_COMPONENTS = (
    ElectricMeterComponentGt,
    SimPicoBtuMeterComponentGt,
    SimPicoFlowModuleComponentGt,
    SimPicoTankModuleComponentGt,
    SimSensorComponentGt,
)


class PlantLayout(NamedTuple):
    """The plant's view of a layout: who it is, which scada it serves, the
    channels it shows that scada with the device that senses each, the
    relays it hears from it with what each one's two positions are, and the
    hydronic plant those belong to. Interior to the plant; every field is
    read off the layout word."""

    g_node: GNodeGt
    scada_alias: LeftRightDot
    telemetry_by_channel: dict[SpaceheatName, TelemetryName]
    sensor_by_channel: dict[SpaceheatName, SensingComponent]
    relay_names: frozenset[SpaceheatName]
    config_by_relay: dict[SpaceheatName, RelayControlConfig]
    hydronic: Hydronic


def g_node_of_class(layout: Layout, g_node_class: GwGNodeClass) -> GNodeGt:
    found = [g for g in layout.g_nodes if g.g_node_class == g_node_class.value]
    if len(found) != 1:
        raise ValueError(
            f"layout has {len(found)} {g_node_class.value} GNodes, expected one"
        )
    return found[0]


def plant_layout(layout: Layout) -> PlantLayout:
    """A channel is the plant's to show when the component of the node that
    captures it is a sensing device of a simulated type. A relay's state
    and an output's level are the scada's own and stay out. The layout
    word holds every channel of a disabled node in DisabledChannelNames, so
    the channel list alone decides what is left out."""
    simulated = set(SimDeviceType.values())
    sensor_by_component_id: dict[str, SensingComponent] = {
        c.component_id: c
        for c in layout.components
        if isinstance(c, SENSING_COMPONENTS) and c.device_type in simulated
    }
    sensor_by_node = {
        n.name: sensor_by_component_id[n.component_id]
        for n in layout.sh_nodes
        if n.component_id in sensor_by_component_id
    }
    disabled_channels = set(layout.disabled_channel_names)
    shown = [
        ch
        for ch in layout.data_channels
        if ch.captured_by_node_name in sensor_by_node
        and ch.name not in disabled_channels
    ]
    return PlantLayout(
        g_node=g_node_of_class(layout, GwGNodeClass.TerminalAsset),
        scada_alias=g_node_of_class(layout, GwGNodeClass.Scada).alias,
        telemetry_by_channel={ch.name: ch.telemetry_name for ch in shown},
        sensor_by_channel={
            ch.name: sensor_by_node[ch.captured_by_node_name] for ch in shown
        },
        relay_names=frozenset(
            n.name for n in layout.sh_nodes if n.actor_class == ActorClass.Relay
        ),
        config_by_relay={
            config.actor_name: config
            for c in layout.components
            if isinstance(c, (I2cRelayComponentGt, GpioRelayComponentGt))
            for config in c.config_list
        },
        hydronic=layout.hydronic,
    )


def load_layout(path: Path) -> Layout:
    decoded = SemaCodec().from_dict(json.loads(path.read_text()))
    if not isinstance(decoded, LAYOUT_WORDS):
        raise ValueError(
            f"{path} holds a {type(decoded).__name__}, and a plant reads a "
            f"{' or a '.join(word.__name__ for word in LAYOUT_WORDS)}"
        )
    return decoded


def load_plant_layout(path: Path) -> PlantLayout:
    return plant_layout(load_layout(path))
