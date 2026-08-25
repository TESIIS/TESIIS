# syntax=docker/dockerfile:1.7

FROM ghcr.io/cirruslabs/flutter:stable@sha256:46691e311715845de03a3ba4753a475476936805b29431b1f00f1816981033f8 AS build

ARG API_BASE_URL=/api
ARG BUILD_SHA=local

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY lib ./lib
COPY assets ./assets
COPY web ./web

RUN flutter build web --release \
    --base-href /app/ \
    --dart-define=API_BASE_URL=${API_BASE_URL} && \
    printf '{"sha":"%s"}\n' "${BUILD_SHA}" > /app/build/web/build-info.json

FROM nginx:1.29-alpine AS runtime

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY landing /usr/share/nginx/html
COPY --from=build /app/build/web /usr/share/nginx/html/app

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --quiet --spider http://127.0.0.1:8080/healthz || exit 1
