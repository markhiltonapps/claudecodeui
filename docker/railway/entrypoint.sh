#!/bin/bash
# Runs as root only long enough to make the volume writable by the app user,
# then drops privileges and starts the server. HOME and WORKSPACES_ROOT are
# pinned to the volume here as well, in case the platform overrides the
# image's environment for the runtime user.
set -e

export HOME="${HOME:-/data}"
export WORKSPACES_ROOT="${WORKSPACES_ROOT:-$HOME}"
mkdir -p "$HOME/.cloudcli" "$HOME/.claude" "$HOME/projects"

if [ "$(id -u)" = "0" ]; then
  # Only walk the whole volume when its owner is wrong (first boot), so a
  # restart with many cloned repos does not spend minutes in chown.
  if [ "$(stat -c %u "$HOME")" != "$(id -u cloudcli)" ]; then
    chown -R cloudcli:cloudcli "$HOME"
  fi
  chown cloudcli:cloudcli "$HOME/.cloudcli" "$HOME/.claude" "$HOME/projects"
  exec gosu cloudcli env HOME="$HOME" WORKSPACES_ROOT="$WORKSPACES_ROOT" "$@"
fi

exec "$@"
