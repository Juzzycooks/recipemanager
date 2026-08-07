#!/bin/sh
# Drop root privileges before running the app.
# PUID/PGID default to 99/100 (Unraid's nobody:users convention).
set -e

PUID="${PUID:-99}"
PGID="${PGID:-100}"

if [ "$(id -u)" = "0" ]; then
    # Ensure a group with PGID exists
    if ! getent group "$PGID" >/dev/null 2>&1; then
        addgroup -g "$PGID" app
    fi
    GROUP_NAME="$(getent group "$PGID" | cut -d: -f1)"

    # Ensure a user with PUID exists
    if ! getent passwd "$PUID" >/dev/null 2>&1; then
        adduser -D -H -G "$GROUP_NAME" -u "$PUID" app
    fi

    mkdir -p /app/data
    chown -R "$PUID:$PGID" /app/data

    exec su-exec "$PUID:$PGID" "$@"
fi

exec "$@"
