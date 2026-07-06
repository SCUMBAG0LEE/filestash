# =============================================================================
# Filestash - Heroku Dockerfile
# Multi-stage build: compile from local source → slim production image
# =============================================================================

# STAGE 1: Build the Go backend from local source
FROM golang:1.26-trixie AS builder
WORKDIR /home/filestash/
COPY . .
RUN apt-get update > /dev/null && \
    apt-get install -y curl make git > /dev/null 2>&1 && \
    apt-get install -y libjpeg-dev libtiff-dev libpng-dev libwebp-dev libraw-dev libheif-dev libgif-dev libvips-dev > /dev/null 2>&1 && \
    apt-get install -y libavcodec-dev libavdevice-dev libavfilter-dev libavformat-dev libswresample-dev libswscale-dev libavutil-dev > /dev/null 2>&1

# Heroku strips .git from build context, so `git rev-parse HEAD` produces empty BUILD_REF
# which causes a panic at static.go:251 (BUILD_REF[0:7] on empty string).
# Fix: if .git is missing, generate a fallback constants_generated.go before build.
RUN if [ ! -d .git ]; then \
        HASH=$(date +%s | sha1sum | awk '{print $1}'); \
        DATE=$(date +%Y%m%d); \
        printf 'package common\n\nfunc init() {\n    BUILD_REF = "%s"\n    BUILD_DATE = "%s"\n}\n' \
            "$HASH" "$DATE" > server/common/constants_generated.go; \
    fi

RUN make init && \
    make build && \
    mkdir -p ./dist/data/state/config/

# Copy the Heroku-specific pre-seeded config (passthrough auth + S3 attribute mapping)
RUN cp heroku/config.json ./dist/data/state/config/config.json

# STAGE 2: Production image
FROM debian:stable-slim
WORKDIR /app/
COPY --from=builder /home/filestash/dist/ .
RUN apt-get update > /dev/null && \
    apt-get -y upgrade > /dev/null && \
    apt-get install -y --no-install-recommends ca-certificates curl ffmpeg libbrotli1 && \
    useradd filestash && \
    chown -R filestash:filestash /app/ && \
    find /app/data/ -type d -exec chmod 770 {} \; && \
    find /app/data/ -type f -exec chmod 760 {} \; && \
    chmod 730 /app/filestash && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/*

USER filestash
CMD ["/app/filestash"]
