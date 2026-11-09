"""Settings for gridworks-terminalasset."""

from gwbase.config import GNodeSettings
from gwbase.transport_format import LeftRightDot
from pydantic_settings import SettingsConfigDict


class GwtaSettings(GNodeSettings):
    """Reads from env (GWTA_*) and/or a `.env` file at the repo root.

    Inherits `rabbit: RabbitBrokerClient`, `g_node_path`, `log_level` and
    the rest of `ServiceSettings` from `GNodeSettings`. A terminal asset is
    a GNode: `service_alias` MUST match the Alias in its `g.node.gt.json`,
    which `GridworksActor` enforces at boot.
    """

    service_alias: LeftRightDot = "d1.hello.ta"
    service_name: str = "terminalasset"  # XDG path segment for logs/state

    # The supervisor whose heartbeats this actor answers, and the clock it
    # marches to.
    super_alias: LeftRightDot = "d1.super1"
    time_coordinator_alias: LeftRightDot = "d1.time"

    model_config = SettingsConfigDict(
        env_prefix="GWTA_",
        env_nested_delimiter="__",
        extra="ignore",
    )

    @classmethod
    def load(cls) -> "GwtaSettings":
        """Settings from env and `.env`. The fields with no default are what
        pyright reads as missing constructor arguments; the settings
        sources supply them, so this is the one place that call is made."""
        return cls()  # pyright: ignore[reportCallIssue]
