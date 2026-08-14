# syntax=docker/dockerfile:1.7

FROM dart:3.12.2 AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get --enforce-lockfile

COPY bin ./bin
COPY lib ./lib

RUN mkdir -p build && dart compile exe bin/server.dart -o build/server

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build --chown=nobody:nogroup /app/build/server ./server
COPY --chown=nobody:nogroup data/shelter_coordinates.csv ./data/shelter_coordinates.csv

ENV PORT=8080 \
    COORDINATES_CSV=data/shelter_coordinates.csv \
    CACHE_TTL_SECONDS=600 \
    LOG_LEVEL=info

USER nobody:nogroup

EXPOSE 8080
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD curl --fail --silent http://127.0.0.1:8080/healthz >/dev/null || exit 1

ENTRYPOINT ["/app/server"]
