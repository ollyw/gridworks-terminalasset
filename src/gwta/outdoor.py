"""Outdoor air for the plant, taken from a weather forecast.

The plant polls the weather service for the bundle it is given and reads
that bundle's temperature series. Each slice is a point at the slice's
start; between two points the temperature moves in a straight line, and
outside the points it holds the nearest one. The service's words are
``gw.weather.forecast.bundle.gt`` and ``gw.weather.forecast``. This
snapshot does not vendor them, so the fields the outdoor temperature
needs are read here, and this module goes when the seed takes the words.
"""

import json
import logging
import threading
import urllib.error
import urllib.request
from collections.abc import Callable
from datetime import datetime
from typing import NamedTuple, Protocol

from gwta.sema.enums import Quantity, Unit

LOGGER = logging.getLogger(__name__)

OUTDOOR_INPUT = "TOutdoor"
KELVIN_AT_0_C = 273.15

# Whole degrees per scaled integer, for the temperature units a bundle's
# observation channel uses.
FAHRENHEIT_DIVISOR: dict[Unit, float] = {
    Unit.FahrenheitX10: 10.0,
    Unit.FahrenheitX100: 100.0,
}

POLL_S = 900.0
RETRY_S = 15.0
PULL_TIMEOUT_S = 10.0


class _Body(Protocol):
    def read(self) -> bytes: ...

    def close(self) -> None: ...


Opener = Callable[..., _Body]


class TemperaturePoint(NamedTuple):
    """Outdoor air at one instant: unix seconds, kelvin."""

    time_s: float
    kelvin: float


def interpolate(points: list[TemperaturePoint], now_s: float) -> float:
    """Kelvin at now_s. A straight line between neighbouring points, the
    nearest point outside them."""
    if not points:
        raise ValueError("a forecast with no temperature points")
    if now_s <= points[0].time_s:
        return points[0].kelvin
    if now_s >= points[-1].time_s:
        return points[-1].kelvin
    for left, right in zip(points, points[1:], strict=False):
        if left.time_s <= now_s <= right.time_s:
            span = right.time_s - left.time_s
            if span == 0:
                return right.kelvin
            share = (now_s - left.time_s) / span
            return left.kelvin + share * (right.kelvin - left.kelvin)
    return points[-1].kelvin


def fahrenheit_to_kelvin(fahrenheit: float) -> float:
    return (fahrenheit - 32.0) * 5.0 / 9.0 + KELVIN_AT_0_C


def _unix_s(iso: str) -> float:
    return datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()


def _temperature_binding(bundle: dict) -> tuple[str, Unit, list[int]]:
    if bundle.get("TypeName") != "gw.weather.forecast.bundle.gt":
        raise ValueError(
            f"not a gw.weather.forecast.bundle.gt: {bundle.get('TypeName')!r}"
        )
    for binding in bundle["BindingList"]:
        observed = binding["ObservationChannel"]
        if Quantity(observed["Quantity"]) != Quantity.Temperature:
            continue
        unit = Unit(observed["Unit"])
        if unit not in FAHRENHEIT_DIVISOR:
            raise ValueError(
                f"temperature channel {observed['Name']} is {unit.value}, "
                "which this plant does not read"
            )
        durations = [int(d) for d in binding["ForecastChannel"]["SliceDurationSList"]]
        return binding["ForecastChannel"]["Name"], unit, durations
    raise ValueError(f"bundle {bundle.get('Name')!r} binds no temperature channel")


def temperature_points(bundle: dict, forecast: dict) -> list[TemperaturePoint]:
    """The forecast's temperature series as points in kelvin, one at each
    slice start the bundle's grid and the series both cover."""
    if forecast.get("TypeName") != "gw.weather.forecast":
        raise ValueError(f"not a gw.weather.forecast: {forecast.get('TypeName')!r}")
    if forecast.get("BundleName") != bundle.get("Name"):
        raise ValueError(
            f"forecast is for {forecast.get('BundleName')!r}, "
            f"bundle is {bundle.get('Name')!r}"
        )
    channel, unit, durations = _temperature_binding(bundle)
    series = next(
        (
            one
            for one in forecast["SeriesList"]
            if one["ChannelName"] == channel
            and Quantity(one["Quantity"]) == Quantity.Temperature
        ),
        None,
    )
    if series is None:
        raise ValueError(f"forecast has no series for {channel}")
    divisor = FAHRENHEIT_DIVISOR[unit]
    count = min(len(durations), len(series["Values"]))
    if count == 0:
        raise ValueError(f"forecast series {channel} has no slices")
    start_s = _unix_s(forecast["FirstSliceStart"])
    points: list[TemperaturePoint] = []
    for duration_s, raw in zip(
        durations[:count], series["Values"][:count], strict=True
    ):
        points.append(
            TemperaturePoint(start_s, fahrenheit_to_kelvin(int(raw) / divisor))
        )
        start_s += duration_s
    return points


def _read_json(url: str, timeout_s: float, opener: Opener) -> object:
    response = opener(url, timeout=timeout_s)
    try:
        body = response.read()
    finally:
        close = getattr(response, "close", None)
        if close is not None:
            close()
    return json.loads(body)


def pull_temperature_points(
    api_url: str,
    bundle_name: str,
    *,
    timeout_s: float = PULL_TIMEOUT_S,
    opener: Opener = urllib.request.urlopen,
) -> list[TemperaturePoint]:
    """The latest forecast's temperature points for bundle_name."""
    base = api_url.rstrip("/")
    listed = _read_json(f"{base}/bundles", timeout_s, opener)
    if not isinstance(listed, list):
        raise ValueError(f"{base}/bundles did not return a list")
    bundle = next((item for item in listed if item.get("Name") == bundle_name), None)
    if bundle is None:
        raise ValueError(f"the weather service has no bundle {bundle_name}")
    forecast = _read_json(f"{base}/latest-forecast/{bundle_name}", timeout_s, opener)
    if not isinstance(forecast, dict):
        raise ValueError(f"latest forecast for {bundle_name} is not an object")
    return temperature_points(bundle, forecast)


class WeatherOutdoor:
    """A bundle's outdoor temperature, refreshed on its own thread.

    ``kelvin_at`` is the interpolated forecast, or None until the first
    pull succeeds. A failed pull keeps the points already held and tries
    again sooner than a success does.
    """

    def __init__(self, api_url: str, bundle_name: str) -> None:
        self.api_url = api_url
        self.bundle_name = bundle_name
        self._points: list[TemperaturePoint] | None = None
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        self._thread = threading.Thread(
            target=self._run, name="weather-outdoor", daemon=True
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=PULL_TIMEOUT_S + 1)

    def kelvin_at(self, now_s: float) -> float | None:
        with self._lock:
            points = self._points
        if points is None:
            return None
        return interpolate(points, now_s)

    def _pull(self) -> bool:
        try:
            points = pull_temperature_points(self.api_url, self.bundle_name)
        except (OSError, urllib.error.URLError, ValueError, KeyError, TypeError) as e:
            LOGGER.warning("weather pull for %s failed: %s", self.bundle_name, e)
            return False
        with self._lock:
            self._points = points
        LOGGER.info(
            "weather %s: %d temperature points from %.0f K",
            self.bundle_name,
            len(points),
            points[0].kelvin,
        )
        return True

    def _run(self) -> None:
        while not self._stop.is_set():
            ok = self._pull()
            self._stop.wait(POLL_S if ok else RETRY_S)
