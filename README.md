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
connects and emits a heartbeat, and `ta-plant`, a simulated plant whose
values either drift at random or are the physics of a Katahdin house.

## The simulated plant

```shell
GWTA_SERVICE_ALIAS=<the layout's TerminalAsset alias> \
  uv run ta-plant --layout <hardware-layout.json>
```

The plant reads one house's hardware layout (a `gw.house0.layout`, a
`gw.house0.no.sieg` or a `gw.katahdin.layout`) and speaks two words, both
wrapped in a `gw` envelope on `amq.topic`:

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
actuations in, channel values out, with no knowledge of the broker. There
are two. `DriftModel` is a seeded random walk per channel inside bounds set
by the channel's telemetry, which keeps the actuations it hears and does
not act on them. `FmuPlantModel` is the physics of a Katahdin house.

## The Katahdin plant

```shell
scripts/build_fmu.sh
GWTA_SERVICE_ALIAS=<the layout's TerminalAsset alias> \
  uv run ta-plant --layout <katahdin-layout.json> --fmu build/KatahdinPlant.fmu
```

A Katahdin house is a monobloc heat pump on a glycol loop, a plate
exchanger, a secondary pump, three store tanks in series, a zoned
distribution loop with its own circulator, five motorised valves (V1 to V5)
and an oil boiler or immersion elements as backup. Its physics is one
Modelica model, `modelica/Katahdin.mo`, with no library behind it:

- **Water moves where the valves and pumps send it.** The pipework is a
  pressure network solved at every instant, so a flow splits between the
  store and the house by their resistances, reverses through the store
  when the house draws more than the exchanger gives, and stops when a
  pump has nowhere to send it.
- **Heat follows the water.** Each store tank is nine layers that keep
  their stratification, mixing only where a warmer layer lies under a
  colder one. The heat pump's capacity and COP are tables over outdoor
  temperature and leaving glycol temperature, and its compressor stops at
  a leaving-temperature limit. Each zone is a thermostat with a deadband,
  an emitter and a room that loses heat to the outdoors.
- **What it leaves out:** the immersion elements, a firing boiler (the
  boiler is a volume of water on its branch), defrost, the heat pump's
  start-up losses and valve travel time.

`scripts/build_fmu.sh` compiles the model with OpenModelica, in docker, to
`build/KatahdinPlant.fmu`: an FMI 2.0 co-simulation FMU that carries its own
variable-step solver, so what the plant does is the same whether `ta-plant`
steps it every second or every minute. `src/gwta/fmu_model.py` runs an FMU
as a `PlantModel`; `src/gwta/katahdin.py` says which FMU output each
channel of a Katahdin layout reads and which FMU input each relay drives;
`src/gwta/sensing.py` gives a tank module's thermistor voltage and a flow
meter's pulse rate for the channels that carry those.

`modelica/Hydronic.mo` is a library of the parts of a heating plant (pipes,
valves, check valves, pumps, flow meters, tanks, a plate exchanger, heat
pumps, a boiler, a zoned house), each with an icon, for a Modelica tool such
as OMEdit or Dymola. Two plants are built of it, each a placed diagram of
connected parts:

- `KatahdinComponents.Plant` (`modelica/KatahdinComponents.mo`) is the
  Katahdin house, with the inputs, outputs and parameters of
  `Katahdin.Plant`.
- `Beech.Plant` (`modelica/Beech.mo`) is a House0 plant, Beech: a split
  heat pump behind a Siegenthaler valve, a buffer, three store tanks behind
  an ISO valve and a charge/discharge valve, an oil boiler with its own
  pump, and two zones, each part placed where the plant's schematic draws
  it. Its inputs are what the relays and the 0-10 V outputs do (the heat
  pump's call, the Siegenthaler valve's motor and direction, the
  charge/discharge relay, each pump, each zone's call, the boiler's call);
  its outputs are the temperatures, flows and powers the house senses. Its
  coefficients are placeholders.

The FMU is built from `Katahdin.mo`. `ta-plant` runs a Katahdin house and
no other; the FMU build checks that both component plants translate.

A relay acts through its contact. `katahdin.py` holds what a closed contact
does (it feeds a valve's motor, runs the secondary pump, calls the heat
pump), and the layout's `relay.control.config` says which of the relay's two
positions closes it. A valve with no feed rests where the house's failsafe
needs it. In a house with a boiler the call reaches the heat pump only
while the boiler backup's failsafe relay is energised; de-energised, the
heat pump is its aquastat's, and the model has the aquastat make no call.

Every coefficient is a parameter of the model with a placeholder value:
pipe resistances, pump curves, tank and exchanger conductances, the heat
pump tables, the zones' heat loss. `--fmu-overrides <file.json>` replaces
any of them, and any input no relay drives, at start:

```json
{"UAExchanger": 2500, "COPTable[2,1]": 2.4, "TOutdoor": 263.15, "TStartPlant": 318.15}
```

The values are SI (kelvin, m3/s, W, Pa); the parameters and their meanings
are the declarations at the top of `model Plant`, and a table is set one
cell at a time. The outdoor temperature (`TOutdoor`) and the two pump
speeds (`secondaryPumpSpeed`, `distPumpSpeed`, each 0 to 1) are inputs that
hold their start value through a run: no word carries them to the plant.

The plant refuses, by name, a layout it cannot serve: one with a channel
the model has no value for, one with a number of zone circuits other than
the four the FMU is generated with, one that does not say which position of
a relay closes its contact, and an override that names neither a parameter
nor an input free of a relay.

### A Katahdin layout

```shell
uv run ta-katahdin-layout \
  --house0 tests/config/gw.house0.no.sieg.hazel.layout.json \
  --ltn-alias d1.isone.ct.newhaven.larch1 \
  --zones north south east west \
  --out tests/config/gw.katahdin.larch.layout.json
```

`ta-katahdin-layout` (`src/gwta/katahdin_layout.py`) makes a
`gw.katahdin.layout` from a House0 layout. The scada's own nodes, the relay
board, the meters and the simulated sensors are the House0 house's; the
pipework is a Katahdin house's: the five valves on the board's free relays,
a 0-10 V output for the secondary pump, the heat pump's control box, three
80-gallon store tanks and one call circuit for each zone named. What a
Katahdin house has no part for is left behind. `--no-boiler` gives a house
with no backup and no boiler valve. Ids are made from the alias and each
thing's name, so the same arguments give the same file.

`tests/config/gw.katahdin.larch.layout.json` is the output of the command
above, and a test holds it to that. Larch is no real house: its alias, its
zones and where its relays sit on the board are the generator's.

### In a container

```shell
docker build -t gwta-plant .
docker run --rm --network host \
  -e GWTA_SERVICE_ALIAS=<the layout's TerminalAsset alias> \
  -v <dir holding the layout>:/layouts:ro \
  gwta-plant --layout /layouts/<katahdin-layout.json> \
  --fmu /opt/gwta/KatahdinPlant.fmu
```

The image generates the FMU and installs the package beside it; its
entrypoint is `ta-plant`. The FMU's binary is for Linux on the processor it
was built on, so the FMU from `scripts/build_fmu.sh` loads on a Linux host
and, on a Mac, the container is the place to run it.

## Development

Requires Python 3.12+ and [uv](https://docs.astral.sh/uv/).

```shell
uv sync
./ci.sh
```

`ci.sh` is the gate: ruff, ruff format, pyright, the FMU build and the
test suite, including the `live` tests, which need the dev RabbitMQ on
`localhost:5672` (start it with gridworks-base's `arm.sh` or `x86.sh`), and
the `fmu` tests, which need docker to generate the FMU. The GitHub workflow
runs the same script against the same broker image, so a local pass is a CI
pass. `uv run pytest` alone runs the offline tests.
