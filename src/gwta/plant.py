"""A simulated plant: the terminal asset of one house, on the broker only.

Run it with::

    uv run ta-plant --layout <hardware-layout.json>

On a timer it publishes a ``sim.plant.flux`` carrying a value for every
channel a simulated sensing device in the layout captures, and it takes
each ``sim.plant.actuation`` addressed to it. Both ride the wrapped ``gw``
grammar on ``amq.topic``, where MQTT peers meet AMQP ones. Channel names
and relay node names are all that cross: what a relay does, the plant
works out from the layout.

With no more than a layout the values drift at random. With ``--fmu`` they
are the physics of a Katahdin house, run from the FMU that
``scripts/build_fmu.sh`` generates::

    uv run ta-plant --layout <katahdin-layout.json> --fmu build/KatahdinPlant.fmu

``GWTA_SERVICE_ALIAS`` must be the alias of the layout's TerminalAsset
GNode, whose ``g.node.gt`` the plant writes to ``GWTA_G_NODE_PATH`` when
that file is absent.
"""

import argparse
import json
import logging
import threading
import time
from collections.abc import Callable
from datetime import UTC, datetime
from pathlib import Path

from gwbase.gridworks_actor import GridworksActor
from gwbase.sema.enums import GwGNodeClass
from gwbase.sema.types.gridworks_header import GridworksHeader
from gwbase.transport_encoding import RoutingEnvelope, WrappedRoutingEnvelope
from gwbase.wrapped import wrap_bytes
from pydantic import TypeAdapter

from gwta.config import GwtaSettings
from gwta.hello import provision_topology, wait_for_consuming
from gwta.katahdin import katahdin_model
from gwta.plant_layout import PlantLayout, load_plant_layout
from gwta.plant_model import DriftModel, PlantModel
from gwta.sema.base import SemaError
from gwta.sema.codec import SemaCodec
from gwta.sema.property_format import UTCMilliseconds
from gwta.sema.types import GNodeGt, SimPlantActuation, SimPlantFlux

LOGGER = logging.getLogger(__name__)

DEFAULT_FLUX_SECONDS = 5.0
DEFAULT_SEED = 0

OVERRIDES = TypeAdapter(dict[str, float])

FLUX_TYPE_NAME = "sim.plant.flux"
ACTUATION_TYPE_NAME = "sim.plant.actuation"


def lrh(alias: str) -> str:
    return alias.replace(".", "-")


def actuation_binding_key(scada_alias: str, plant_alias: str) -> str:
    return WrappedRoutingEnvelope(
        type_name=ACTUATION_TYPE_NAME,
        from_alias=scada_alias,
        to_class_token=lrh(plant_alias),
    ).routing_key


def wall_ms() -> UTCMilliseconds:
    return int(time.time() * 1000)


def wall_time_utc() -> str:
    return datetime.now(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def write_g_node_json(path: Path, g_node: GNodeGt) -> Path:
    """Write the plant's identity file from the layout's own TerminalAsset
    GNode if none exists."""
    if path.exists():
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(g_node.to_dict(), indent=2))
    return path


class SimulatedPlant(GridworksActor):
    """The transport around a plant model. The model is reached from two
    threads, the consumer's for actuations and the caller's for flux, so
    every call into it holds the lock."""

    def __init__(
        self,
        *,
        settings: GwtaSettings,
        layout: PlantLayout,
        model: PlantModel,
        now_ms: Callable[[], UTCMilliseconds],
    ):
        if settings.service_alias != layout.g_node.alias:
            raise ValueError(
                f"GWTA_SERVICE_ALIAS {settings.service_alias!r} is not the layout's "
                f"TerminalAsset {layout.g_node.alias!r}"
            )
        super().__init__(
            settings=settings,
            g_node_class=GwGNodeClass.TerminalAsset,
            my_super_alias=settings.super_alias,
            my_time_coordinator_alias=settings.time_coordinator_alias,
        )
        self.layout = layout
        self.model = model
        self.now_ms = now_ms
        self.model_lock = threading.Lock()
        self.codec = SemaCodec()

    def local_rabbit_startup(self) -> None:
        super().local_rabbit_startup()
        self.subscribe_amq_topic(
            binding_key=actuation_binding_key(self.layout.scada_alias, self.alias)
        )

    def process_message(
        self,
        *,
        envelope: RoutingEnvelope,
        body: bytes,
        header: GridworksHeader | None,  # noqa: ARG002 -- the header is not read
    ) -> None:
        if envelope.type_name != ACTUATION_TYPE_NAME:
            LOGGER.info(
                "[%s] ignored %s from %s",
                self.alias,
                envelope.type_name,
                envelope.from_alias,
            )
            return
        try:
            actuation = self.codec.from_dict(json.loads(body), expect=SimPlantActuation)
        except (SemaError, ValueError) as e:
            LOGGER.warning(
                "[%s] dropped a malformed %s: %s", self.alias, ACTUATION_TYPE_NAME, e
            )
            return
        if actuation.relay_name not in self.layout.relay_names:
            LOGGER.warning(
                "[%s] dropped an actuation of %s, which is no relay of this layout",
                self.alias,
                actuation.relay_name,
            )
            return
        LOGGER.info(
            "[%s] heard %s %s", self.alias, actuation.relay_name, actuation.action.value
        )
        with self.model_lock:
            self.model.actuate(actuation)

    def next_flux(self) -> SimPlantFlux:
        now_ms = self.now_ms()
        with self.model_lock:
            values = self.model.step(now_ms)
        return SimPlantFlux(
            channel_name_list=list(values),
            value_list=list(values.values()),
            scada_read_time_unix_ms=now_ms,
            actual_time_utc=wall_time_utc(),
        )

    def emit_flux(self) -> None:
        flux = self.next_flux()
        self.send(
            envelope=WrappedRoutingEnvelope(
                type_name=flux.type_name,
                from_alias=self.alias,
                to_class_token=lrh(self.layout.scada_alias),
            ),
            body=wrap_bytes(
                src=self.alias,
                dst=self.layout.scada_alias,
                inner_type_name=flux.type_name,
                inner_payload_dict=flux.to_dict(),
            ),
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--layout", type=Path, required=True, help="the house's hardware layout"
    )
    parser.add_argument(
        "--flux-seconds",
        type=float,
        default=DEFAULT_FLUX_SECONDS,
        help=f"flux cadence (default {DEFAULT_FLUX_SECONDS})",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=DEFAULT_SEED,
        help=f"seed of the drift (default {DEFAULT_SEED})",
    )
    parser.add_argument(
        "--fmu",
        type=Path,
        help="the Katahdin plant's FMU; without it the values drift at random",
    )
    parser.add_argument(
        "--fmu-overrides",
        type=Path,
        help="a JSON object of FMU parameter and input values that replace "
        "the FMU's own",
    )
    parser.add_argument(
        "--no-provision",
        action="store_true",
        help="skip declaring the exchange topology (it already exists)",
    )
    args = parser.parse_args()
    if args.fmu_overrides is not None and args.fmu is None:
        parser.error("--fmu-overrides needs --fmu")

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    logging.getLogger("pika").setLevel(logging.WARNING)

    settings = GwtaSettings.load()
    layout = load_plant_layout(args.layout)
    write_g_node_json(settings.g_node_path, layout.g_node)

    if not args.no_provision:
        provision_topology(settings.rabbit.url.get_secret_value())

    model: PlantModel
    if args.fmu is None:
        model = DriftModel(layout.telemetry_by_channel, seed=args.seed)
    else:
        overrides = (
            {}
            if args.fmu_overrides is None
            else OVERRIDES.validate_json(args.fmu_overrides.read_bytes())
        )
        model = katahdin_model(
            fmu_path=args.fmu, layout=layout, overrides=overrides, start_ms=wall_ms()
        )
    plant = SimulatedPlant(
        settings=settings,
        layout=layout,
        model=model,
        now_ms=wall_ms,
    )
    plant.start()
    try:
        wait_for_consuming(plant)
        LOGGER.info(
            "[%s] consuming; %d channels every %.1fs to %s",
            plant.alias,
            len(layout.telemetry_by_channel),
            args.flux_seconds,
            layout.scada_alias,
        )
        while True:
            plant.emit_flux()
            time.sleep(args.flux_seconds)
    except KeyboardInterrupt:
        LOGGER.info("[%s] interrupted; stopping", plant.alias)
    finally:
        plant.stop()
        model.close()


if __name__ == "__main__":
    main()
