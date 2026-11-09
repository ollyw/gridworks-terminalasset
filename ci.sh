#!/usr/bin/env bash
#
# The gate for this repo: the GitHub workflow runs this script and nothing
# else, so a local pass is a CI pass. Run it before committing.
#
# The live tests need the dev broker on localhost:5672 (gridworks-base
# arm.sh / x86.sh; CI runs the same baked image as a service container).
#
# Usage: ./ci.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

step() { printf '\n=== %s ===\n' "$1"; shift; "$@"; }

step "uv sync (locked)" uv sync --all-groups --locked
step "ruff check" uv run ruff check --no-fix --no-cache .
step "ruff format --check" uv run ruff format --check --no-cache .
step "pyright" uv run pyright

if ! nc -z localhost 5672 2>/dev/null; then
  echo "ERROR: no broker on localhost:5672 — start the dev rabbit (gridworks-base arm.sh or x86.sh)." >&2
  exit 1
fi
# -o addopts="" lifts pyproject's default `-m 'not live'` so the live tests run too.
step "tests (offline + live)" uv run pytest -q -o addopts=""

printf '\nAll checks passed.\n'
