"""Outdoor temperature from a weather forecast: points at slice starts,
a straight line between them."""

import json
from datetime import UTC, datetime, timedelta

from gwta.outdoor import (
    TemperaturePoint,
    fahrenheit_to_kelvin,
    interpolate,
    pull_temperature_points,
    temperature_points,
)

START = datetime(2026, 11, 18, 15, 0, tzinfo=UTC)


def iso(moment: datetime) -> str:
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def bundle_and_forecast(raw: list[int]) -> tuple[dict, dict]:
    return (
        {
            "TypeName": "gw.weather.forecast.bundle.gt",
            "Name": "us.me.millinocket.moose",
            "BindingList": [
                {
                    "ForecastChannel": {
                        "Name": "kmlt.temperature.forecast.nws.hourly96",
                        "SliceDurationSList": [3600] * len(raw),
                    },
                    "ObservationChannel": {
                        "Name": "kmlt.temperature",
                        "Quantity": "Temperature",
                        "Unit": "FahrenheitX10",
                    },
                }
            ],
        },
        {
            "TypeName": "gw.weather.forecast",
            "BundleName": "us.me.millinocket.moose",
            "FirstSliceStart": iso(START),
            "SeriesList": [
                {
                    "ChannelName": "kmlt.temperature.forecast.nws.hourly96",
                    "Quantity": "Temperature",
                    "Values": raw,
                }
            ],
        },
    )


def test_between_points_the_temperature_is_the_straight_line() -> None:
    points = temperature_points(*bundle_and_forecast([320, 500]))
    assert points[0] == TemperaturePoint(START.timestamp(), fahrenheit_to_kelvin(32))
    halfway = START + timedelta(minutes=30)
    assert interpolate(points, halfway.timestamp()) == fahrenheit_to_kelvin(41)


def test_outside_the_points_the_temperature_holds() -> None:
    points = temperature_points(*bundle_and_forecast([320, 500]))
    before = (START - timedelta(hours=2)).timestamp()
    after = (START + timedelta(hours=5)).timestamp()
    assert interpolate(points, before) == fahrenheit_to_kelvin(32)
    assert interpolate(points, after) == fahrenheit_to_kelvin(50)


class Response:
    def __init__(self, payload: object) -> None:
        self.payload = json.dumps(payload).encode()

    def read(self) -> bytes:
        return self.payload

    def close(self) -> None:
        return None


def test_the_pull_reads_the_bundle_and_its_latest_forecast() -> None:
    bundle, forecast = bundle_and_forecast([400])

    def opener(url: str, timeout: float) -> Response:  # noqa: ARG001
        if url.endswith("/bundles"):
            return Response([bundle])
        return Response(forecast)

    points = pull_temperature_points(
        "http://weather/d1-weather",
        "us.me.millinocket.moose",
        opener=opener,
    )
    assert points == [TemperaturePoint(START.timestamp(), fahrenheit_to_kelvin(40))]
