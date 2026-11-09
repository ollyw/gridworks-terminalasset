import json

import pytest
from gwbase.sema import GwBaseSemaCodec
from gwbase.sema.enums import GwGNodeClass
from gwbase.sema.types import GNodeGt

from gwta.config import GwtaSettings
from gwta.hello import HelloTerminalAsset, ensure_g_node_json, provision_topology


@pytest.fixture
def settings(tmp_path) -> GwtaSettings:
    path = ensure_g_node_json(tmp_path / "g.node.gt.json", alias="d1.test.ta")
    return GwtaSettings(service_alias="d1.test.ta", g_node_path=path)


def test_g_node_json_is_sema_valid(tmp_path):
    path = ensure_g_node_json(tmp_path / "g.node.gt.json", alias="d1.test.ta")
    g = GwBaseSemaCodec().from_dict(json.loads(path.read_text()), mode="strict")
    assert isinstance(g, GNodeGt)
    assert g.g_node_class == "TerminalAsset"
    assert g.alias == "d1.test.ta"


def test_ensure_is_idempotent(tmp_path):
    path = ensure_g_node_json(tmp_path / "g.node.gt.json", alias="d1.test.ta")
    first = path.read_text()
    ensure_g_node_json(path, alias="d1.other.ta")  # no overwrite
    assert path.read_text() == first


def test_hello_constructs_without_broker(settings):
    ta = HelloTerminalAsset(settings=settings)
    assert ta.alias == "d1.test.ta"
    assert ta.g_node_class == GwGNodeClass.TerminalAsset


@pytest.mark.live
def test_hello_beats_on_live_broker(settings):
    from gwta.hello import wait_for_consuming

    provision_topology(settings.rabbit.url.get_secret_value())
    ta = HelloTerminalAsset(settings=settings)
    ta.start()
    try:
        wait_for_consuming(ta)
        ta.beat()
    finally:
        ta.stop()
