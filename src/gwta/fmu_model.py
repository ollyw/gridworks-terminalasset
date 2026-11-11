"""A plant model whose physics is a co-simulation FMU (FMI 2.0).

The FMU is the plant in SI units and knows nothing of channels or relays.
This module is its edge: a relay actuation becomes an input value at the
instant the relay moved, an output becomes a channel reading in the
channel's encoding, and simulated time advances to whatever instant the
caller names.
"""

import shutil
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import NamedTuple

from fmpy import extract, read_model_description
from fmpy.fmi2 import FMU2Slave

from gwta.plant_model import PlantModel
from gwta.sema.enums import ChangeRelayPin, TelemetryName
from gwta.sema.property_format import SpaceheatName, UTCMilliseconds
from gwta.sema.types import SimPlantActuation

# An FMU built by OpenModelica looks for its own events (a thermostat
# closing, a compressor cutting out) only at the end of a step, so a long
# advance is taken in pieces no longer than this and what the model does
# stays the same whatever cadence the caller keeps.
MAX_FMU_STEP_S = 5.0

KELVIN_AT_0_C = 273.15
M3_PER_S_PER_GPM = 6.30902e-5

ENCODER_BY_UNIT_AND_TELEMETRY: dict[
    tuple[str | None, TelemetryName], Callable[[float], int]
] = {
    ("K", TelemetryName.CelsiusTimes100): lambda k: round((k - KELVIN_AT_0_C) * 100),
    ("K", TelemetryName.WaterTempCTimes1000): lambda k: round(
        (k - KELVIN_AT_0_C) * 1000
    ),
    ("K", TelemetryName.AirTempCTimes1000): lambda k: round((k - KELVIN_AT_0_C) * 1000),
    ("m3/s", TelemetryName.GpmTimes100): lambda q: round(q / M3_PER_S_PER_GPM * 100),
    ("W", TelemetryName.PowerW): round,
}


class DeviceEncoding(NamedTuple):
    """How a sensing device turns a plant value into what its channel
    carries, where that is the device's own reading and not a change of
    unit: the unit it takes the value in and the conversion."""

    unit: str
    encode: Callable[[float], int]


class RelayEffect(NamedTuple):
    """What one relay does to the plant: the FMU input it drives and the
    value that input takes in each of the relay's two states."""

    variable: str
    energized: float
    de_energized: float


class FmuPlantModel(PlantModel):
    """One running instance of an FMU, started with every relay
    de-energized. `variable_by_channel` names the FMU output each channel
    reads. A channel in `encoding_by_channel` is encoded as its sensing
    device does and every other one by its telemetry. `effect_by_relay`
    names what each relay drives, and a relay it leaves out moves nothing.
    `overrides` replace the FMU's own values for
    parameters, and for inputs that no relay drives, before the run
    starts."""

    def __init__(
        self,
        *,
        fmu_path: Path,
        telemetry_by_channel: Mapping[SpaceheatName, TelemetryName],
        variable_by_channel: Mapping[SpaceheatName, str],
        encoding_by_channel: Mapping[SpaceheatName, DeviceEncoding],
        effect_by_relay: Mapping[SpaceheatName, RelayEffect],
        overrides: Mapping[str, float],
        start_ms: UTCMilliseconds,
    ) -> None:
        description = read_model_description(str(fmu_path))
        if description.coSimulation is None:
            raise ValueError(f"{fmu_path} is not a co-simulation FMU")
        variables = {v.name: v for v in description.modelVariables}

        unbound = sorted(set(telemetry_by_channel) - set(variable_by_channel))
        if unbound:
            raise ValueError(f"the plant has no value for: {', '.join(unbound)}")
        self.reference_by_channel: dict[SpaceheatName, int] = {}
        self.encoder_by_channel: dict[SpaceheatName, Callable[[float], int]] = {}
        for channel, telemetry in telemetry_by_channel.items():
            name = variable_by_channel[channel]
            variable = variables.get(name)
            if variable is None or variable.causality != "output":
                raise ValueError(
                    f"{channel} reads {name}, which is no output of {fmu_path.name}"
                )
            encoding = encoding_by_channel.get(channel)
            if encoding is None:
                encoder = ENCODER_BY_UNIT_AND_TELEMETRY.get((variable.unit, telemetry))
            elif encoding.unit == variable.unit:
                encoder = encoding.encode
            else:
                raise ValueError(
                    f"{channel} is encoded from {encoding.unit}, and {name} is "
                    f"in {variable.unit}"
                )
            if encoder is None:
                raise ValueError(
                    f"{channel} is {telemetry.value}, and no encoding takes "
                    f"{name} ({variable.unit}) to it"
                )
            self.reference_by_channel[channel] = variable.valueReference
            self.encoder_by_channel[channel] = encoder

        self.effect_by_relay = dict(effect_by_relay)
        driven = {effect.variable for effect in self.effect_by_relay.values()}
        for relay, effect in self.effect_by_relay.items():
            variable = variables.get(effect.variable)
            if variable is None or variable.causality != "input":
                raise ValueError(
                    f"{relay} drives {effect.variable}, which is no input of "
                    f"{fmu_path.name}"
                )
        for name in overrides:
            variable = variables.get(name)
            settable = variable is not None and (
                variable.causality == "parameter"
                or (variable.causality == "input" and name not in driven)
            )
            if not settable:
                raise ValueError(
                    f"{name} is not a parameter of {fmu_path.name}, nor an input "
                    "that no relay drives"
                )
        self.reference_by_variable = {
            name: variable.valueReference for name, variable in variables.items()
        }

        self.start_ms = start_ms
        self.time_s = 0.0
        self.unzip_directory = extract(str(fmu_path))
        self.fmu = FMU2Slave(
            guid=description.guid,
            unzipDirectory=self.unzip_directory,
            modelIdentifier=description.coSimulation.modelIdentifier,
            instanceName=fmu_path.stem,
        )
        self.fmu.instantiate()
        self.fmu.setupExperiment(startTime=0.0)
        self.set_values(
            dict(overrides)
            | {
                effect.variable: effect.de_energized
                for effect in self.effect_by_relay.values()
            }
        )
        self.fmu.enterInitializationMode()
        self.fmu.exitInitializationMode()

    def set_values(self, value_by_variable: Mapping[str, float]) -> None:
        if value_by_variable:
            self.fmu.setReal(
                [self.reference_by_variable[name] for name in value_by_variable],
                list(value_by_variable.values()),
            )

    def advance_to(self, now_ms: UTCMilliseconds) -> None:
        """Run the FMU up to now_ms. Time does not run backwards: an instant
        the model is already past leaves it where it is."""
        target_s = (now_ms - self.start_ms) / 1000
        while self.time_s < target_s:
            step_s = min(MAX_FMU_STEP_S, target_s - self.time_s)
            self.fmu.doStep(
                currentCommunicationPoint=self.time_s, communicationStepSize=step_s
            )
            self.time_s += step_s

    def step(self, now_ms: UTCMilliseconds) -> dict[SpaceheatName, int]:
        self.advance_to(now_ms)
        values = self.fmu.getReal(list(self.reference_by_channel.values()))
        return {
            channel: self.encoder_by_channel[channel](value)
            for channel, value in zip(self.reference_by_channel, values, strict=True)
        }

    def actuate(self, actuation: SimPlantActuation) -> None:
        effect = self.effect_by_relay.get(actuation.relay_name)
        if effect is None:
            return
        self.advance_to(actuation.actuation_time_unix_ms)
        energized = actuation.action == ChangeRelayPin.Energize
        self.set_values(
            {effect.variable: effect.energized if energized else effect.de_energized}
        )

    def read(self, variable: str) -> float:
        """The present value of any FMU variable, in the FMU's own unit."""
        [value] = self.fmu.getReal([self.reference_by_variable[variable]])
        return value

    def close(self) -> None:
        self.fmu.terminate()
        self.fmu.freeInstance()
        shutil.rmtree(self.unzip_directory, ignore_errors=True)
