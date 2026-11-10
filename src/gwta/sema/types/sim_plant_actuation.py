from typing import Literal
from gwta.sema.base import SemaType
from gwta.sema.enums import ChangeRelayPin
from gwta.sema.property_format import SpaceheatName
from gwta.sema.property_format import UTCMilliseconds
from gwta.sema.property_format import UtcIso8601Millis


class SimPlantActuation(SemaType):
    """Sema: https://schemas.electricity.works/types/sim.plant.actuation/000"""

    relay_name: SpaceheatName
    action: ChangeRelayPin
    actuation_time_unix_ms: UTCMilliseconds
    actual_time_utc: UtcIso8601Millis
    type_name: Literal["sim.plant.actuation"] = "sim.plant.actuation"
    version: Literal["000"] = "000"
