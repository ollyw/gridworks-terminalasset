from typing import Literal
from pydantic import StrictFloat
from gwta.sema.base import SemaType
from gwta.sema.property_format import PositiveInt
from gwta.sema.property_format import UUID4Str
from gwta.sema.types.maker_api_attribute_gt import MakerApiAttributeGt


class HubitatPollerGt(SemaType):
    """Sema: https://schemas.electricity.works/types/hubitat.poller.gt/001"""

    hubitat_component_id: UUID4Str
    device_id: PositiveInt
    attributes: list[MakerApiAttributeGt]
    web_listen_enabled: bool
    poll_period_seconds: StrictFloat
    type_name: Literal["hubitat.poller.gt"] = "hubitat.poller.gt"
    version: Literal["001"] = "001"
