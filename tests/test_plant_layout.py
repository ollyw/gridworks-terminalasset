"""The plant's reading of a layout. The fixtures are gridworks-scada's
House0 test layouts (its tests/config), byte for byte: hazel with no
Siegenthaler loop, orange with one."""

import json
from pathlib import Path

import pytest

from gwta.plant_layout import load_plant_layout, plant_layout
from gwta.plant_model import DriftModel
from gwta.sema.codec import SemaCodec
from gwta.sema.enums import TelemetryName
from gwta.sema.types import House0NoSieg

CONFIG = Path(__file__).parent / "config"
LAYOUT_PATH = CONFIG / "gw.house0.no.sieg.hazel.layout.json"
SIEG_LAYOUT_PATH = CONFIG / "gw.house0.orange.layout.json"
SENSING_ACTORS = {"PowerMeter", "SimSensorActor", "ApiTankModule", "ApiBtuMeter"}


def raw_layout() -> dict:
    return json.loads(LAYOUT_PATH.read_text())


def decoded(raw: dict) -> House0NoSieg:
    return SemaCodec().from_dict(raw, expect=House0NoSieg)


def test_the_plant_is_the_layouts_terminal_asset_and_serves_its_scada() -> None:
    layout = load_plant_layout(LAYOUT_PATH)
    assert layout.g_node.alias == "d1.isone.ct.newhaven.hazel1.ta"
    assert layout.g_node.g_node_class == "TerminalAsset"
    assert layout.scada_alias == "d1.isone.ct.newhaven.hazel1.scada"


def test_the_plant_shows_what_simulated_sensing_devices_capture() -> None:
    raw = raw_layout()
    capturers = {n["Name"]: n["ActorClass"] for n in raw["ShNodes"]}
    expected = {
        ch["Name"]
        for ch in raw["DataChannels"]
        if capturers[ch["CapturedByNodeName"]] in SENSING_ACTORS
    }
    shown = load_plant_layout(LAYOUT_PATH).telemetry_by_channel
    assert set(shown) == expected
    assert len(shown) == 35
    assert shown["hp-odu-pwr"] == TelemetryName.PowerW
    assert shown["secondary-flow"] == TelemetryName.GpmTimes100


def test_relay_states_and_output_levels_are_not_the_plants_to_show() -> None:
    shown = load_plant_layout(LAYOUT_PATH).telemetry_by_channel
    assert TelemetryName.RelayState not in shown.values()
    assert TelemetryName.VoltsTimesTen not in shown.values()
    assert not {"vdc-relay", "store-pump-relay", "dist-010v", "store-010v"} & set(shown)


def test_the_plant_hears_every_relay_of_the_layout() -> None:
    raw = raw_layout()
    relays = {n["Name"] for n in raw["ShNodes"] if n["ActorClass"] == "Relay"}
    assert load_plant_layout(LAYOUT_PATH).relay_names == relays
    assert len(relays) == 11


def test_a_real_device_type_takes_its_channels_out_of_the_plant() -> None:
    raw = raw_layout()
    meter = next(
        c for c in raw["Components"] if c["TypeName"] == "electric.meter.component.gt"
    )
    record = next(
        t for t in raw["DeviceTypes"] if t["DeviceType"] == meter["DeviceType"]
    )
    meter["DeviceType"] = record["DeviceType"] = "EgaugeEg4030"
    shown = plant_layout(decoded(raw)).telemetry_by_channel
    assert len(shown) == 29
    assert "hp-odu-pwr" not in shown


def test_disabled_channels_are_left_out() -> None:
    raw = raw_layout()
    raw["DisabledChannelNames"] = ["buffer-depth1-micro-v"]
    shown = plant_layout(decoded(raw)).telemetry_by_channel
    assert "buffer-depth1-micro-v" not in shown
    assert len(shown) == 34


def test_a_file_that_is_another_word_is_refused(tmp_path: Path) -> None:
    path = tmp_path / "layout.json"
    path.write_text(json.dumps(raw_layout()["GNodes"][0]))
    with pytest.raises(
        ValueError,
        match="holds a GNodeGt, and a plant reads a House0Layout or a House0NoSieg",
    ):
        load_plant_layout(path)


def test_a_house_with_a_sieg_loop_is_read_the_same_way() -> None:
    raw = json.loads(SIEG_LAYOUT_PATH.read_text())
    assert raw["TypeName"] == "gw.house0.layout"
    capturers = {n["Name"]: n["ActorClass"] for n in raw["ShNodes"]}
    layout = load_plant_layout(SIEG_LAYOUT_PATH)

    assert layout.g_node.alias == "d1.isone.ct.newhaven.orange1.ta"
    assert layout.scada_alias == "d1.isone.ct.newhaven.orange1.scada"
    assert set(layout.telemetry_by_channel) == {
        ch["Name"]
        for ch in raw["DataChannels"]
        if capturers[ch["CapturedByNodeName"]] in SENSING_ACTORS
    }
    assert len(layout.telemetry_by_channel) == 36
    assert layout.relay_names == {
        n["Name"] for n in raw["ShNodes"] if n["ActorClass"] == "Relay"
    }
    assert {"hp-loop-on-off-relay", "hp-loop-keep-send-relay"} <= layout.relay_names


def test_the_model_has_a_walk_for_every_channel_of_a_sieg_house() -> None:
    layout = load_plant_layout(SIEG_LAYOUT_PATH)
    model = DriftModel(layout.telemetry_by_channel, seed=7)
    assert set(model.step(1_794_300_000_000)) == set(layout.telemetry_by_channel)
