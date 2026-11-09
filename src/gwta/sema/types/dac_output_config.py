from typing import Literal
from gwta.sema.base import SemaType
from gwta.sema.enums import I2cDacChannel
from gwta.sema.property_format import SpaceheatName


class DacOutputConfig(SemaType):
    """Sema: https://schemas.electricity.works/types/dac.output.config/000"""

    channel_name: SpaceheatName
    actor_name: SpaceheatName
    dac_channel: I2cDacChannel
    type_name: Literal["dac.output.config"] = "dac.output.config"
    version: Literal["000"] = "000"
