"""The inside of a simulated plant: time and relay actuations in, channel
values out. A model knows nothing of brokers or message envelopes, so one
is tested by calling it and replaced without touching the transport."""

import random
from abc import ABC, abstractmethod
from collections.abc import Mapping
from typing import NamedTuple

from gwta.sema.enums import TelemetryName
from gwta.sema.property_format import SpaceheatName, UTCMilliseconds
from gwta.sema.types import SimPlantActuation


class PlantModel(ABC):
    @abstractmethod
    def step(self, now_ms: UTCMilliseconds) -> dict[SpaceheatName, int]:
        """Advance to now_ms and return every channel's value, each in its
        channel's own encoding."""

    @abstractmethod
    def actuate(self, actuation: SimPlantActuation) -> None:
        """Take one relay actuation."""

    def close(self) -> None:
        """Release what the model holds outside Python: nothing, unless a
        model says otherwise."""


class Drift(NamedTuple):
    """The random walk of one kind of channel, in that telemetry's encoding:
    where it starts, the bounds it stays inside and the most it moves in
    one step."""

    start: int
    low: int
    high: int
    max_step: int


DRIFT_BY_TELEMETRY: dict[TelemetryName, Drift] = {
    TelemetryName.CelsiusTimes100: Drift(
        start=5_000, low=1_000, high=8_500, max_step=10
    ),
    TelemetryName.GpmTimes100: Drift(start=400, low=0, high=1_200, max_step=10),
    TelemetryName.MicroHz: Drift(
        start=2_000_000, low=0, high=10_000_000, max_step=50_000
    ),
    TelemetryName.MicroVolts: Drift(
        start=1_200_000, low=300_000, high=2_500_000, max_step=2_000
    ),
    TelemetryName.PowerW: Drift(start=500, low=0, high=6_000, max_step=50),
}


class DriftModel(PlantModel):
    """No physics: every channel walks at random inside the bounds of its
    telemetry. It keeps the actuations it hears and does not act on them.
    The seed makes a run repeatable."""

    def __init__(
        self, telemetry_by_channel: Mapping[SpaceheatName, TelemetryName], seed: int
    ) -> None:
        unknown = sorted(
            f"{name} ({telemetry.value})"
            for name, telemetry in telemetry_by_channel.items()
            if telemetry not in DRIFT_BY_TELEMETRY
        )
        if unknown:
            raise ValueError(
                f"no drift bounds for the telemetry of: {', '.join(unknown)}"
            )
        self.drift_by_channel = {
            name: DRIFT_BY_TELEMETRY[telemetry]
            for name, telemetry in telemetry_by_channel.items()
        }
        self.values = {
            name: drift.start for name, drift in self.drift_by_channel.items()
        }
        self.random = random.Random(seed)
        self.actuations: list[SimPlantActuation] = []

    def step(self, now_ms: UTCMilliseconds) -> dict[SpaceheatName, int]:  # noqa: ARG002
        for name, drift in self.drift_by_channel.items():
            moved = self.values[name] + self.random.randint(
                -drift.max_step, drift.max_step
            )
            self.values[name] = min(drift.high, max(drift.low, moved))
        return dict(self.values)

    def actuate(self, actuation: SimPlantActuation) -> None:
        self.actuations.append(actuation)
