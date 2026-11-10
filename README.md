# gridworks-terminalasset

A GridWorks **terminal asset** actor: the avatar for a real-world transactive
device — a heating system, a thermal store, an EV charger — represented as a
GNode that communicates over a RabbitMQ broker.

In the GridWorks fleet, a SCADA reports on behalf of a terminal asset and an
aggregator or leaf transactive node trades on its behalf. This repo holds the
terminal asset itself as a service built on
[gridworks-base](https://github.com/thegridelectric/gridworks-base).

## First use: simulated terminal assets

The first inhabitants of this repo are **simulated** terminal assets: actors
that model a (deliberately simple) heating system and publish synthetic sensor
telemetry over a broker, so that a whole house — terminal asset, sensors,
SCADA control — can be stood up in software and exercised end to end. The
simulated assets double as traffic generators for communications experiments:
tunable emission cadence, scriptable silence, and burst modes are first-class
features.

The longer arc is a hybrid fleet where simulated houses run alongside real
ones on the same brokers, indistinguishable in their communication patterns.

Message types are governed by **Sema** — the versioned vocabulary of
JSON-Schema contracts for all GridWorks message boundaries, canonical at
[`thegridelectric/sema`](https://github.com/thegridelectric/sema) (schema
ids under `https://schemas.electricity.works`). This repo carries a vendored
snapshot at `src/gwta/sema` — generated, never hand-edit; regenerate with
`scripts/regen_sema_snapshot.sh` from the seed
`src/gwta/sema_seed_request.yaml`. See `src/gwta/sema/README.md` for the
working rules.

## Status

Early. Two actors run against a dev RabbitMQ broker: `ta-hello`, which
connects and emits a heartbeat, and `ta-plant`, a simulated plant with no
physics yet.

## The simulated plant

```shell
GWTA_SERVICE_ALIAS=<the layout's TerminalAsset alias> \
  uv run ta-plant --layout <hardware-layout.json>
```

The plant reads one house's hardware layout (a `gw.house0.no.sieg`) and
speaks two words, both wrapped in a `gw` envelope on `amq.topic`:

- `sim.plant.flux`, every `--flux-seconds`: a value for each enabled channel
  that a simulated sensing device captures, in the channel's own encoding.
  Routing key `gw.<plant>.to.<scada>.sim-plant-flux`, aliases with their
  dots as hyphens.
- `sim.plant.actuation`, taken from
  `gw.<scada>.to.<plant>.sim-plant-actuation`: a relay's node name and
  whether it was energised or de-energised.

Channel names and relay node names are all that cross the broker. A relay's
state and an output's level are never in the flux.

The plant's inside is a `PlantModel` (`src/gwta/plant_model.py`): time and
actuations in, channel values out, with no knowledge of the broker. Today
that is `DriftModel`, a seeded random walk per channel inside bounds set by
the channel's telemetry, which keeps the actuations it hears and does not
act on them.

## Development

Requires Python 3.12+ and [uv](https://docs.astral.sh/uv/).

```shell
uv sync
./ci.sh
```

`ci.sh` is the gate: ruff, ruff format, pyright and the test suite,
including the `live` tests, which need the dev RabbitMQ on
`localhost:5672` (start it with gridworks-base's `arm.sh` or `x86.sh`).
The GitHub workflow runs the same script against the same broker image,
so a local pass is a CI pass. `uv run pytest` alone runs the offline
tests.
