# syntax=docker/dockerfile:1
#
# Two things come out of this file:
#
#   the FMU alone      docker build --target fmu-file --output build .
#                      (what scripts/build_fmu.sh runs)
#   the plant image    docker build -t gwta-plant .
#
# The image holds the gwta package and the Katahdin FMU at
# /opt/gwta/KatahdinPlant.fmu, and runs ta-plant. The FMU's binary is for
# Linux on the processor the build ran on, which is the processor the image
# is for.

FROM openmodelica/openmodelica:v1.27.1-minimal AS fmu
WORKDIR /work
COPY modelica/ ./
RUN omc build_fmu.mos && test -f KatahdinPlant.fmu

FROM scratch AS fmu-file
COPY --from=fmu /work/KatahdinPlant.fmu /

FROM python:3.12-slim-bookworm AS plant
COPY --from=ghcr.io/astral-sh/uv:0.12.23 /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
WORKDIR /app
COPY pyproject.toml uv.lock README.md LICENSE ./
COPY src/ src/
RUN uv sync --locked --no-dev --no-editable
COPY --from=fmu /work/KatahdinPlant.fmu /opt/gwta/KatahdinPlant.fmu

RUN useradd --create-home gwta
USER gwta
WORKDIR /home/gwta
ENV PATH="/app/.venv/bin:$PATH"
ENTRYPOINT ["ta-plant"]
