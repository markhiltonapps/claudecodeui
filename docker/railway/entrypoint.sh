#!/bin/bash
# Runs as root only long enough to make the volume writable by the app user,
# then drops privileges and starts the server.
set -e

DATA_DIR="${HOME:-/data}"
mkdir -p "$DATA_DIR/.cloudcli" "$DATA_DIR/.claude" "$DATA_DIR/projects"

if [ "$(id -u)" = "0" ]; then
  chown -R cloudcli:cloudcli "$DATA_DIR"
  exec gosu cloudcli "$@"
fi

exec "$@"
