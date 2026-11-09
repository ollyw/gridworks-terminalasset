"""Hello-world terminal asset: connect to a rabbit broker, beat a heartbeat.

Run it with::

    uv run ta-hello

Against the default broker URL (a local dev rabbit:
``amqp://smqPublic:smqPublic@localhost:5672/d1__1``) or wherever
``GWTA_RABBIT__URL`` points. The actor provisions the exchange topology,
connects, and broadcasts a ``heartbeat.a`` every ``--beat-seconds`` until
interrupted. No physics — this actor exists to prove the comms plumbing.
"""

import argparse
import itertools
import json
import logging
import time
import uuid
from pathlib import Path

import pika
from gwbase import topology
from gwbase.gridworks_actor import GridworksActor
from gwbase.sema.enums import GwGNodeClass
from gwbase.sema.types import HeartbeatA
from gwbase.sema.types.gridworks_header import GridworksHeader
from gwbase.transport_encoding import RoutingEnvelope

from gwta.config import GwtaSettings

LOGGER = logging.getLogger(__name__)

DEFAULT_BEAT_SECONDS = 10.0


def ensure_g_node_json(path: Path, *, alias: str) -> Path:
    """Write a dev TerminalAsset ``g.node.gt.json`` at path if none exists.

    TerminalAsset is a physical GNode class, so the instance carries a
    PositionPointId. A throwaway dev identity — real terminal assets get
    provisioned, not self-minted.
    """
    if path.exists():
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "GNodeId": str(uuid.uuid4()),
                "Alias": alias,
                "GNodeClass": "TerminalAsset",
                "BaseClass": "TerminalAsset",
                "PositionPointId": str(uuid.uuid4()),
                "Status": "Active",
                "TypeName": "g.node.gt",
                "Version": "006",
            },
            indent=2,
        )
    )
    return path


def provision_topology(url: str) -> None:
    """Declare the shared exchange fabric (idempotent) before the actor
    starts — actors only passively assert their consume exchange exists."""
    conn = pika.BlockingConnection(pika.URLParameters(url))
    try:
        ch = conn.channel()
        for ex in topology.exchanges():
            ch.exchange_declare(
                exchange=ex.name,
                exchange_type=ex.exchange_type,
                durable=ex.durable,
                internal=ex.internal,
            )
        for b in topology.exchange_bindings():
            ch.exchange_bind(
                destination=b.destination,
                source=b.source,
                routing_key=b.routing_key,
            )
    finally:
        conn.close()


class HelloTerminalAsset(GridworksActor):
    """The smallest terminal asset: GNode identity, a broker connection,
    and a broadcast ``heartbeat.a`` at a fixed cadence."""

    def __init__(self, *, settings: GwtaSettings):
        super().__init__(
            settings=settings,
            g_node_class=GwGNodeClass.TerminalAsset,
            my_super_alias=settings.super_alias,
            my_time_coordinator_alias=settings.time_coordinator_alias,
        )
        self._hex_cycle = itertools.cycle("0123456789abcdef")

    def process_message(
        self,
        *,
        envelope: RoutingEnvelope,
        body: bytes,  # noqa: ARG002 -- logged by type only
        header: GridworksHeader | None,  # noqa: ARG002 -- the header is not read
    ) -> None:
        LOGGER.info(
            "[%s] received %s from %s",
            self.alias,
            envelope.type_name,
            envelope.from_alias,
        )

    def beat(self) -> None:
        hb = HeartbeatA(my_hex=next(self._hex_cycle), your_last_hex=None)
        self.send(
            envelope=self.broadcast_envelope(type_name=hb.type_name),
            body=hb.to_bytes(),
        )
        LOGGER.info("[%s] beat %s", self.alias, hb.my_hex)


def wait_for_consuming(actor: GridworksActor, timeout_s: float = 10.0) -> None:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if actor._consuming:  # noqa: SLF001
            return
        time.sleep(0.05)
    raise RuntimeError(f"{actor.alias} did not start consuming within {timeout_s}s")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--beat-seconds",
        type=float,
        default=DEFAULT_BEAT_SECONDS,
        help=f"heartbeat cadence (default {DEFAULT_BEAT_SECONDS})",
    )
    parser.add_argument(
        "--no-provision",
        action="store_true",
        help="skip declaring the exchange topology (it already exists)",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    logging.getLogger("pika").setLevel(logging.WARNING)

    settings = GwtaSettings.load()
    ensure_g_node_json(settings.g_node_path, alias=settings.service_alias)

    if not args.no_provision:
        provision_topology(settings.rabbit.url.get_secret_value())

    ta = HelloTerminalAsset(settings=settings)
    ta.start()
    try:
        wait_for_consuming(ta)
        LOGGER.info("[%s] consuming; beating every %.1fs", ta.alias, args.beat_seconds)
        while True:
            ta.beat()
            time.sleep(args.beat_seconds)
    except KeyboardInterrupt:
        LOGGER.info("[%s] interrupted; stopping", ta.alias)
    finally:
        ta.stop()


if __name__ == "__main__":
    main()
