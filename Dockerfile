# =============================================================================
# Filestash - Heroku Dockerfile
# Multi-stage build: compile from local source → slim production image
# =============================================================================

# STAGE 1: Build the Go backend from local source
FROM golang:1.26-trixie AS builder
WORKDIR /home/filestash/
COPY . .
RUN apt-get update > /dev/null && \
    apt-get install -y curl make > /dev/null 2>&1 && \
    apt-get install -y libjpeg-dev libtiff-dev libpng-dev libwebp-dev libraw-dev libheif-dev libgif-dev libvips-dev > /dev/null 2>&1 && \
    apt-get install -y libavcodec-dev libavdevice-dev libavfilter-dev libavformat-dev libswresample-dev libswscale-dev libavutil-dev > /dev/null 2>&1

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
