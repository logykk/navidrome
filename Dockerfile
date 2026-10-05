FROM docker.io/library/node@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1 AS ui
WORKDIR /app
COPY ui/package.json ui/package-lock.json ./
COPY ui/bin/ ./bin/
RUN npm ci
COPY ui/ ./
RUN npm run build -- --outDir=/build

FROM docker.io/library/golang@sha256:8a5910f31396cd4d89662f56c68b3ae31d374308270a1c3bd96672ee5ed43414 AS build
WORKDIR /workspace
RUN apk add --no-cache build-base git zlib-dev taglib-dev
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
COPY --from=ui /build ./ui/build
ARG GIT_SHA
ARG GIT_TAG
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    set -e; \
    BUILD_TAGS="$(./release/build-tags.sh)"; \
    CGO_ENABLED=1 go build -tags="${BUILD_TAGS}" -ldflags="-w -s \
        -X github.com/navidrome/navidrome/consts.gitSha=${GIT_SHA} \
        -X github.com/navidrome/navidrome/consts.gitTag=${GIT_TAG}" \
        -o /out/navidrome .

FROM docker.io/library/alpine@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8 AS final
LABEL maintainer="deluan@navidrome.org"
LABEL org.opencontainers.image.source="https://github.com/navidrome/navidrome"
RUN apk add --no-cache curl ffmpeg mpv sqlite libwebp libwebpdemux libwebpmux taglib && \
    for lib in libwebp libwebpdemux libwebpmux; do \
        target=$(ls /usr/lib/$lib.so.* 2>/dev/null | head -1) && \
        [ -n "$target" ] && ln -sf "$target" /usr/lib/$lib.so; \
    done
COPY --from=build /out/navidrome /app/navidrome
VOLUME ["/data", "/music"]
ENV ND_MUSICFOLDER=/music
ENV ND_DATAFOLDER=/data
ENV ND_CONFIGFILE=/data/navidrome.toml
ENV ND_PORT=4533
RUN touch /.nddockerenv
EXPOSE 4533
WORKDIR /app
ENV PATH="/app:${PATH}"
ENTRYPOINT ["/app/navidrome"]
