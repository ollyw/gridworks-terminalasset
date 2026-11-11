"""What a simulated sensing device reports where its channel carries the
device's own electrical reading and not the quantity it measures: a tank
module's thermistor voltage, a flow meter's pulse rate.
"""

import math
from collections.abc import Callable

from gwta.fmu_model import KELVIN_AT_0_C, M3_PER_S_PER_GPM, DeviceEncoding
from gwta.plant_layout import PlantLayout, SensingComponent
from gwta.sema.enums import GpmFromHzMethod, TelemetryName, TempCalcMethod
from gwta.sema.property_format import SpaceheatName
from gwta.sema.types import (
    SimPicoBtuMeterComponentGt,
    SimPicoFlowModuleComponentGt,
    SimPicoTankModuleComponentGt,
    SimSensorComponentGt,
)

# A tank module's thermistor circuit: 10 kOhm at 298 K, in a divider with
# 5.65 kOhm across the pico's 3.3 V, and a module that takes 0 C as 273 K.
# Hand-kept: pico.tank.module.component.gt carries the thermistor's beta and
# nothing of its divider, and a word for the divider retires these.
THERMISTOR_R0_KOHMS = 10.0
THERMISTOR_T0_K = 298.0
DIVIDER_KOHMS = 5.65
PICO_VOLTS = 3.3
MODULE_KELVIN_AT_0_C = 273.0

# The meter behind a flow that a sim.sensor.component.gt reads. Hand-kept:
# that word names no meter, and a flow read by a
# sim.pico.flow.module.component.gt, which does, retires this.
SIM_SENSOR_GALLONS_PER_PULSE = 0.0009


def thermistor_microvolts(beta: int) -> Callable[[float], int]:
    """The divider voltage a tank module reads at a water temperature in
    kelvin, in microvolts."""

    def encode(kelvin: float) -> int:
        module_kelvin = kelvin - KELVIN_AT_0_C + MODULE_KELVIN_AT_0_C
        kohms = THERMISTOR_R0_KOHMS * math.exp(
            beta * (1 / module_kelvin - 1 / THERMISTOR_T0_K)
        )
        return round(PICO_VOLTS * kohms / (DIVIDER_KOHMS + kohms) * 1e6)

    return encode


def pulse_microhertz(gallons_per_pulse: float) -> Callable[[float], int]:
    """The pulse rate of a flow meter at a flow in m3/s, in microhertz."""

    def encode(m3_per_s: float) -> int:
        gallons_per_s = m3_per_s / M3_PER_S_PER_GPM / 60
        return round(gallons_per_s / gallons_per_pulse * 1e6)

    return encode


def device_encoding(
    telemetry: TelemetryName, sensor: SensingComponent
) -> DeviceEncoding | None:
    """The encoding a sensor gives a channel of this telemetry, or None
    where the telemetry alone decides it or the sensor has no reading of
    that kind."""
    if telemetry == TelemetryName.MicroVolts:
        if (
            isinstance(sensor, SimPicoTankModuleComponentGt)
            and sensor.temp_calc_method == TempCalcMethod.SimpleBeta
        ):
            return DeviceEncoding("K", thermistor_microvolts(sensor.thermistor_beta))
    elif telemetry == TelemetryName.MicroHz:
        if isinstance(sensor, SimSensorComponentGt):
            return DeviceEncoding(
                "m3/s", pulse_microhertz(SIM_SENSOR_GALLONS_PER_PULSE)
            )
        if (
            isinstance(sensor, SimPicoFlowModuleComponentGt)
            and sensor.gpm_from_hz_method == GpmFromHzMethod.Constant
        ):
            return DeviceEncoding(
                "m3/s", pulse_microhertz(sensor.constant_gallons_per_tick)
            )
        if (
            isinstance(sensor, SimPicoBtuMeterComponentGt)
            and sensor.gpm_from_hz_method == GpmFromHzMethod.Constant
        ):
            return DeviceEncoding("m3/s", pulse_microhertz(sensor.gallons_per_pulse))
    return None


def device_encodings(layout: PlantLayout) -> dict[SpaceheatName, DeviceEncoding]:
    """The channels of a layout that are encoded as their sensing device
    does."""
    encodings: dict[SpaceheatName, DeviceEncoding] = {}
    for channel, telemetry in layout.telemetry_by_channel.items():
        encoding = device_encoding(telemetry, layout.sensor_by_channel[channel])
        if encoding is not None:
            encodings[channel] = encoding
    return encodings
