import json
import time
from pathlib import Path

import pika
import pytest
from gwbase.transport_encoding import WrappedRoutingEnvelope, parse_routing_key
from gwbase.wrapped import unwrap_bytes, wrap_bytes

from gwta.config import GwtaSettings
from gwta.hello import provision_topology, wait_for_consuming
from gwta.plant import (
    SimulatedPlant,
    actuation_binding_key,
    write_g_node_json,
)
from gwta.plant_layout import PlantLayout, load_plant_layout
from gwta.plant_model import DriftModel
from gwta.sema.codec import SemaCodec
from gwta.sema.enums import ChangeRelayPin
from gwta.sema.types import SimPlantActuation, SimPlantFlux

LAYOUT_PATH = Path(__file__).parent / "config" / "gw.house0.no.sieg.hazel.layout.json"
PLANT_ALIAS = "d1.isone.ct.newhaven.hazel1.ta"
SCADA_ALIAS = "d1.isone.ct.newhaven.hazel1.scada"
NOW_MS = 1_735_689_600_123
FLUX_KEY = "gw.d1-isone-ct-newhaven-hazel1-ta.to.d1-isone-ct-newhaven-hazel1-scada.sim-plant-flux"
ACTUATION_KEY = "gw.d1-isone-ct-newhaven-hazel1-scada.to.d1-isone-ct-newhaven-hazel1-ta.sim-plant-actuation"


@pytest.fixture
def layout() -> PlantLayout:
    return load_plant_layout(LAYOUT_PATH)


@pytest.fixture
def settings(tmp_path: Path, layout: PlantLayout) -> GwtaSettings:
    path = write_g_node_json(tmp_path / "g.node.gt.json", layout.g_node)
    return GwtaSettings(service_alias=PLANT_ALIAS, g_node_path=path)


@pytest.fixture
def plant(settings: GwtaSettings, layout: PlantLayout) -> SimulatedPlant:
    return SimulatedPlant(
        settings=settings,
        layout=layout,
        model=DriftModel(layout.telemetry_by_channel, seed=0),
        now_ms=lambda: NOW_MS,
    )


def actuation_payload(
    relay_name: str = "store-pump-relay", **overrides: object
) -> dict:
    return {
        "RelayName": relay_name,
        "Action": "Energize",
        "ActuationTimeUnixMs": NOW_MS,
        "ActualTimeUtc": "2026-06-12T13:20:00.000Z",
        "TypeName": "sim.plant.actuation",
        "Version": "000",
    } | overrides


def wrapped_actuation(payload: dict) -> bytes:
    return wrap_bytes(
        src=SCADA_ALIAS,
        dst=PLANT_ALIAS,
        inner_type_name=payload["TypeName"],
        inner_payload_dict=payload,
    )


def deliver(
    plant: SimulatedPlant, payload: dict, routing_key: str = ACTUATION_KEY
) -> None:
    plant.dispatch_message(
        envelope=parse_routing_key(routing_key), body=wrapped_actuation(payload)
    )


def drift(plant: SimulatedPlant) -> DriftModel:
    assert isinstance(plant.model, DriftModel)
    return plant.model


def test_the_identity_file_is_the_layouts_terminal_asset(
    tmp_path: Path, layout: PlantLayout
) -> None:
    path = write_g_node_json(tmp_path / "g.node.gt.json", layout.g_node)
    written = json.loads(path.read_text())
    assert written["Alias"] == PLANT_ALIAS
    assert written["GNodeClass"] == "TerminalAsset"
    first = path.read_text()
    write_g_node_json(path, layout.g_node.model_copy(update={"alias": "d1.other.ta"}))
    assert path.read_text() == first


def test_a_plant_is_the_layouts_terminal_asset_or_nothing(
    tmp_path: Path, layout: PlantLayout
) -> None:
    path = write_g_node_json(tmp_path / "g.node.gt.json", layout.g_node)
    settings = GwtaSettings(service_alias="d1.other.ta", g_node_path=path)
    with pytest.raises(ValueError, match="is not the layout's TerminalAsset"):
        SimulatedPlant(
            settings=settings,
            layout=layout,
            model=DriftModel(layout.telemetry_by_channel, seed=0),
            now_ms=lambda: NOW_MS,
        )


def test_a_flux_carries_every_shown_channel_at_the_plants_time(
    plant: SimulatedPlant, layout: PlantLayout
) -> None:
    flux = plant.next_flux()
    assert flux.channel_name_list == list(layout.telemetry_by_channel)
    assert len(flux.value_list) == 35
    assert flux.scada_read_time_unix_ms == NOW_MS
    assert SemaCodec().from_dict(flux.to_dict(), expect=SimPlantFlux) == flux
    assert plant.next_flux().value_list != flux.value_list


def test_routing_keys_are_the_wrapped_grammar_between_plant_and_scada(
    plant: SimulatedPlant,
) -> None:
    assert actuation_binding_key(SCADA_ALIAS, plant.alias) == ACTUATION_KEY
    sent: list[tuple[str, bytes]] = []
    plant.send = lambda *, envelope, body, **_: sent.append(
        (envelope.routing_key, body)
    )  # type: ignore[method-assign]
    plant.emit_flux()
    [(routing_key, body)] = sent
    assert routing_key == FLUX_KEY
    header, payload = unwrap_bytes(body)
    assert (header.src, header.dst, header.ack_required) == (
        PLANT_ALIAS,
        SCADA_ALIAS,
        False,
    )
    assert isinstance(SemaCodec().from_dict(payload, expect=SimPlantFlux), SimPlantFlux)


@pytest.mark.parametrize("action", list(ChangeRelayPin))
def test_an_actuation_reaches_the_model(
    plant: SimulatedPlant, action: ChangeRelayPin
) -> None:
    deliver(plant, actuation_payload(Action=action.value))
    [heard] = drift(plant).actuations
    assert isinstance(heard, SimPlantActuation)
    assert (heard.relay_name, heard.action) == ("store-pump-relay", action)


@pytest.mark.parametrize(
    "payload",
    [
        actuation_payload("no-such-relay"),
        actuation_payload("dist-flow"),
        actuation_payload(ActualTimeUtc="yesterday"),
        actuation_payload(Version="999"),
    ],
    ids=["unknown-relay", "a-channel-name", "malformed", "unknown-version"],
)
def test_what_is_no_actuation_of_this_layout_is_dropped(
    plant: SimulatedPlant, payload: dict
) -> None:
    deliver(plant, payload)
    assert drift(plant).actuations == []


def test_another_word_on_the_plants_queue_is_ignored(plant: SimulatedPlant) -> None:
    flux = plant.next_flux()
    plant.dispatch_message(
        envelope=parse_routing_key(FLUX_KEY),
        body=wrap_bytes(
            src=SCADA_ALIAS,
            dst=PLANT_ALIAS,
            inner_type_name=flux.type_name,
            inner_payload_dict=flux.to_dict(),
        ),
    )
    assert drift(plant).actuations == []


class Listener:
    """A consumer that is neither the plant nor a scada: it binds a queue of
    its own to amq.topic and keeps what arrives."""

    def __init__(self, url: str, binding_key: str) -> None:
        self.connection = pika.BlockingConnection(pika.URLParameters(url))
        self.channel = self.connection.channel()
        self.queue = self.channel.queue_declare("", exclusive=True).method.queue
        self.channel.queue_bind(self.queue, "amq.topic", routing_key=binding_key)

    def next_body(self, timeout_s: float) -> tuple[str, bytes]:
        deadline = time.time() + timeout_s
        while time.time() < deadline:
            method, _, body = self.channel.basic_get(self.queue, auto_ack=True)
            if method is not None and body is not None:
                return method.routing_key, body
            time.sleep(0.05)
        raise AssertionError(f"nothing on {self.queue} within {timeout_s}s")

    def publish(self, routing_key: str, body: bytes) -> None:
        self.channel.basic_publish("amq.topic", routing_key, body)

    def close(self) -> None:
        self.connection.close()


@pytest.mark.live
def test_flux_and_actuation_cross_the_broker(
    plant: SimulatedPlant, layout: PlantLayout
) -> None:
    url = plant.settings.rabbit.url.get_secret_value()
    provision_topology(url)
    listener = Listener(url, FLUX_KEY)
    plant.start()
    try:
        wait_for_consuming(plant)
        plant.emit_flux()
        routing_key, body = listener.next_body(timeout_s=5)
        assert routing_key == FLUX_KEY
        _, payload = unwrap_bytes(body)
        flux = SemaCodec().from_dict(payload, expect=SimPlantFlux)
        assert set(flux.channel_name_list) == set(layout.telemetry_by_channel)

        envelope = WrappedRoutingEnvelope(
            type_name="sim.plant.actuation",
            from_alias=SCADA_ALIAS,
            to_class_token=PLANT_ALIAS.replace(".", "-"),
        )
        deadline = time.time() + 5
        while not drift(plant).actuations and time.time() < deadline:
            listener.publish(
                envelope.routing_key, wrapped_actuation(actuation_payload())
            )
            time.sleep(0.1)
        assert drift(plant).actuations[0].relay_name == "store-pump-relay"
    finally:
        plant.stop()
        listener.close()
