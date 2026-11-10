import pytest

from gwta.plant_model import DRIFT_BY_TELEMETRY, DriftModel
from gwta.sema.enums import ChangeRelayPin, TelemetryName
from gwta.sema.types import SimPlantActuation

CHANNELS = {
    "buffer-depth1": TelemetryName.CelsiusTimes100,
    "dist-flow": TelemetryName.GpmTimes100,
    "dist-flow-hz": TelemetryName.MicroHz,
    "buffer-depth1-micro-v": TelemetryName.MicroVolts,
    "hp-odu-pwr": TelemetryName.PowerW,
}
NOW_MS = 1_735_689_600_000


def walk(model: DriftModel, steps: int) -> list[dict[str, int]]:
    return [model.step(NOW_MS + 5_000 * i) for i in range(steps)]


def actuation(relay_name: str = "store-pump-relay") -> SimPlantActuation:
    return SimPlantActuation(
        relay_name=relay_name,
        action=ChangeRelayPin.Energize,
        actuation_time_unix_ms=NOW_MS,
        actual_time_utc="2026-06-12T13:20:00.000Z",
    )


def test_every_step_reports_every_channel() -> None:
    model = DriftModel(CHANNELS, seed=1)
    for values in walk(model, 5):
        assert list(values) == list(CHANNELS)


def test_the_same_seed_walks_the_same_way() -> None:
    assert walk(DriftModel(CHANNELS, seed=7), 50) == walk(
        DriftModel(CHANNELS, seed=7), 50
    )
    assert walk(DriftModel(CHANNELS, seed=7), 50) != walk(
        DriftModel(CHANNELS, seed=8), 50
    )


def test_values_move_and_stay_inside_their_bounds() -> None:
    history = walk(DriftModel(CHANNELS, seed=3), 5_000)
    for name, telemetry in CHANNELS.items():
        drift = DRIFT_BY_TELEMETRY[telemetry]
        seen = [values[name] for values in history]
        assert drift.low <= min(seen) and max(seen) <= drift.high
        assert len(set(seen)) > 100
        steps = [abs(b - a) for a, b in zip([drift.start, *seen], seen, strict=False)]
        assert max(steps) <= drift.max_step


def test_a_walk_pinned_at_a_bound_stays_on_it() -> None:
    model = DriftModel({"dist-flow": TelemetryName.GpmTimes100}, seed=5)
    model.values["dist-flow"] = 0
    seen = [values["dist-flow"] for values in walk(model, 200)]
    assert min(seen) == 0


def test_actuations_are_kept_and_change_nothing() -> None:
    quiet = DriftModel(CHANNELS, seed=11)
    told = DriftModel(CHANNELS, seed=11)
    first, second = actuation("store-pump-relay"), actuation("hp-scada-ops-relay")
    told.actuate(first)
    before = walk(told, 10)
    told.actuate(second)
    after = walk(told, 10)
    assert before + after == walk(quiet, 20)
    assert told.actuations == [first, second]


def test_a_channel_with_no_drift_bounds_is_refused_by_name() -> None:
    with pytest.raises(ValueError, match=r"vdc-relay \(RelayState\)"):
        DriftModel({"vdc-relay": TelemetryName.RelayState}, seed=0)
