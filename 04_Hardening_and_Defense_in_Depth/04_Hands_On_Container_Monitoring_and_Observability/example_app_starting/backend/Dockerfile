# syntax=docker/dockerfile:1.10

FROM dhi.io/python:3.14.5-debian13-dev@sha256:6fb2fbaf1cbfedeac9b035bdc5538b237385164803254c8d47d784fc7395fe94 AS build

ARG UV_VERSION=0.11.15
ARG UV_INDEX_URL=https://pypi.org/simple

ENV UV_INDEX_URL=${UV_INDEX_URL} \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:${PATH}"

WORKDIR /src

RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --no-cache-dir "uv==${UV_VERSION}"

COPY pyproject.toml uv.lock ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv venv "${VIRTUAL_ENV}" && \
    uv sync --locked --no-dev --no-install-project --active

COPY app.py healthcheck.py ./

RUN python -m compileall -q app.py healthcheck.py

FROM dhi.io/python:3.14.5-debian13@sha256:06affe7f9b2dbca52f8ccdaeb2aef7d0e9096f52121d25a9a97d186fdbbd0827 AS runtime

ARG APP_HOME=/app
ARG APP_UID=10001
ARG APP_GID=10001

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_ENV=production \
    ENABLE_DEBUG_ROUTES=false

WORKDIR ${APP_HOME}

COPY --from=build /opt/venv /opt/venv
COPY --from=build --chown=${APP_UID}:${APP_GID} /src/app.py ${APP_HOME}/app.py
COPY --from=build --chown=${APP_UID}:${APP_GID} /src/healthcheck.py ${APP_HOME}/healthcheck.py

USER ${APP_UID}:${APP_GID}

EXPOSE 8000

ENTRYPOINT ["uvicorn", "app:app"]
CMD ["--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
