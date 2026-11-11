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
    House0Layout,
    House0NoSieg,
    SimPicoBtuMeterComponentGt,
    SimPicoFlowModuleComponentGt,
    SimPicoTankModuleComponentGt,
    SimSensorComponentGt,
)

# The layout words a plant reads: one House0 house, with a Siegenthaler loop
# or without.
House0 = House0Layout | House0NoSieg
HOUSE0_WORDS = (House0Layout, House0NoSieg)

SENSING_COMPONENTS = (
    ElectricMeterComponentGt,
    SimPicoBtuMeterComponentGt,
    SimPicoFlowModuleComponentGt,
    SimPicoTankModuleComponentGt,
    SimSensorComponentGt,
)


class PlantLayout(NamedTuple):
    """The plant's view of a layout: who it is, which scada it serves, the
    channels it shows that scada and the relays it hears from it. Interior
    to the plant; every field is read off the layout word."""

    g_node: GNodeGt
    scada_alias: LeftRightDot
    telemetry_by_channel: dict[SpaceheatName, TelemetryName]
    relay_names: frozenset[SpaceheatName]


def g_node_of_class(layout: House0, g_node_class: GwGNodeClass) -> GNodeGt:
    found = [g for g in layout.g_nodes if g.g_node_class == g_node_class.value]
    if len(found) != 1:
        raise ValueError(
            f"layout has {len(found)} {g_node_class.value} GNodes, expected one"
        )
    return found[0]


def plant_layout(layout: House0) -> PlantLayout:
    """A channel is the plant's to show when the component of the node that
    captures it is a sensing device of a simulated type. A relay's state
    and an output's level are the scada's own and stay out. The layout
    word holds every channel of a disabled node in DisabledChannelNames, so
    the channel list alone decides what is left out."""
    simulated = set(SimDeviceType.values())
    sensing_component_ids = {
        c.component_id
        for c in layout.components
        if isinstance(c, SENSING_COMPONENTS) and c.device_type in simulated
    }
    sensing_nodes = {
        n.name for n in layout.sh_nodes if n.component_id in sensing_component_ids
    }
    disabled_channels = set(layout.disabled_channel_names)
    return PlantLayout(
        g_node=g_node_of_class(layout, GwGNodeClass.TerminalAsset),
        scada_alias=g_node_of_class(layout, GwGNodeClass.Scada).alias,
        telemetry_by_channel={
            ch.name: ch.telemetry_name
            for ch in layout.data_channels
            if ch.captured_by_node_name in sensing_nodes
            and ch.name not in disabled_channels
        },
        relay_names=frozenset(
            n.name for n in layout.sh_nodes if n.actor_class == ActorClass.Relay
        ),
    )


def load_plant_layout(path: Path) -> PlantLayout:
    decoded = SemaCodec().from_dict(json.loads(path.read_text()))
    if not isinstance(decoded, HOUSE0_WORDS):
        raise ValueError(
            f"{path} holds a {type(decoded).__name__}, and a plant reads a "
            f"{' or a '.join(word.__name__ for word in HOUSE0_WORDS)}"
        )
    return plant_layout(decoded)
