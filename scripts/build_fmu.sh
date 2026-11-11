#!/usr/bin/env bash
#
# Generate build/KatahdinPlant.fmu from modelica/Katahdin.mo with the
# OpenModelica compiler, run in the Dockerfile's fmu stage so the host needs
# docker and nothing else. The FMU's binary is for Linux on the host's
# processor: it loads on a Linux host and in a Linux container of the same
# architecture.
#
# Usage: scripts/build_fmu.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker build --target fmu-file --output "$REPO/build" "$REPO"
echo "built $REPO/build/KatahdinPlant.fmu"
