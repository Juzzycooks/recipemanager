# Build stage
FROM python:3.13-alpine AS builder

WORKDIR /app

# Build deps (jpeg/zlib/webp only needed if no Pillow wheel is available)
RUN apk update && apk upgrade --no-cache \
    && apk add --no-cache gcc musl-dev libffi-dev jpeg-dev zlib-dev libwebp-dev

RUN pip install --no-cache-dir --upgrade pip

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Runtime stage
FROM python:3.13-alpine

WORKDIR /app

# Upgrade all system packages and explicitly update vulnerable ones.
# su-exec: drop root after fixing volume permissions (see entrypoint.sh).
# libjpeg-turbo/zlib/libwebp: Pillow runtime libs (no-op if wheels are bundled).
RUN apk update && apk upgrade --no-cache \
    && apk add --no-cache --upgrade openssl libcrypto3 libssl3 sqlite-libs \
    && apk add --no-cache su-exec libjpeg-turbo zlib libwebp

RUN pip install --no-cache-dir --upgrade pip

COPY --from=builder /install /usr/local
COPY . .

RUN mkdir -p /app/data && chmod +x /app/entrypoint.sh

ENV DATA_DIR=/app/data
VOLUME /app/data
EXPOSE 5000

# Container reports unhealthy if the app stops responding
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:5000/login || exit 1

# Starts as root only to chown /app/data, then drops to PUID:PGID (default 99:100)
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "60", "app:create_app()"]
