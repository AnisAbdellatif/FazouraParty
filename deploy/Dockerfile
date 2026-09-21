# The server as an OTP release, with the built Flutter web app inside it.
#
# Build context is the repository root, because the image needs both `server/`
# and `app/build/web` (produced by `dart run tool/build_web.dart`, which is what
# computes the service worker's cache key — never build the web app any other way).
#
#   docker build -f deploy/Dockerfile -t fazoura .

ARG ELIXIR_IMAGE=hexpm/elixir:1.20.4-erlang-29.0.6-debian-trixie-20260824-slim
ARG RUNNER_IMAGE=debian:trixie-20260824-slim
ARG FORCE_SSL=true

FROM ${ELIXIR_IMAGE} AS builder
ARG FORCE_SSL=true

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential git \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /src
ENV MIX_ENV=prod
ENV FORCE_SSL=${FORCE_SSL}

RUN mix local.hex --force && mix local.rebar --force

# Dependencies first, so editing application code doesn't recompile them.
# config.exs and prod.exs come along because `Application.compile_env` reads them.
COPY server/mix.exs server/mix.lock ./
RUN mix deps.get --only prod
COPY server/config/config.exs server/config/prod.exs config/
RUN mix deps.compile

COPY server/priv priv
COPY server/lib lib
RUN mix compile --warnings-as-errors

COPY server/config/runtime.exs config/
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends ca-certificates curl libncurses6 libstdc++6 locales openssl \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

ENV MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=4000 \
    WEB_DIR=/app/web \
    UPLOADS_DIR=/data/uploads \
    PACKAGES_DIR=/data/packages

# Question photos outlive the image: compose.yaml mounts a volume here, and a
# fresh volume inherits this ownership, so `nobody` can still write to it.
RUN mkdir -p /data/uploads && chown -R nobody:root /data

WORKDIR /app
# The release writes its scratch files under the release root, so `nobody` must own it.
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /src/_build/prod/rel/fazoura ./
COPY --chown=nobody:root app/build/web ./web

USER nobody
EXPOSE 4000

CMD ["/app/bin/fazoura", "start"]
