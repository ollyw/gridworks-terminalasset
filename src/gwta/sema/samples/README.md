# Samples

Canonical JSON instances, one per seeded **type** version that carries
an `examples:` block. Generated from the authored examples (never edited
by hand) and consumed by `roundtrip.py`. A type version without a sample
is silently untested by the round-trip, so its absence is recorded here.

Coverage: **67 of 78** seeded type versions have a sample.

Seeded type versions lacking a sample (no `examples:`):

- `ads111x.based.device.type.gt.000`
- `electric.meter.device.type.gt.000`
- `gw.house0.layout.000`
- `gw.house0.no.sieg.000`
- `gw.katahdin.layout.000`
- `gw.native.gpio.pin.000`
- `gw.nolan.layout.000`
- `gw1.hvac.zone.000`
- `gw1.zone.call.circuit.000`
- `gw1.zone.thermostat.000`
- `i2c.bus.000`
