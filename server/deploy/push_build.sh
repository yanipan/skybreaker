#!/usr/bin/env bash
# Export the room server and copy it with the lobby to the VM, then restart.
# Usage: push_build.sh <ssh-target>     e.g. yaniv@34.1.2.3
# Running games are cut off by the restart: do it when /health shows rooms 0.
set -euo pipefail
T="${1:?ssh target}"
SSH_OPTS="${SSH_OPTS:--o BatchMode=yes}"   # pass -i <key> here when the key is not the default
cd "$(dirname "$0")/../.."
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
mkdir -p builds/server
"$G" --headless --path . --export-release "Linux Server" builds/server/skybreaker_server.x86_64 >/dev/null 2>&1 || true
[ -s builds/server/skybreaker_server.pck ] || { echo "export failed"; exit 1; }
ssh $SSH_OPTS "$T" 'mkdir -p /tmp/sb_push'
rsync -az -e "ssh $SSH_OPTS" builds/server/skybreaker_server.x86_64 builds/server/skybreaker_server.pck server/lobby/lobby.js "$T":/tmp/sb_push/
ssh $SSH_OPTS "$T" 'sudo install -o skybreaker -g skybreaker -m 755 /tmp/sb_push/skybreaker_server.x86_64 /opt/skybreaker/bin/ &&
  sudo install -o skybreaker -g skybreaker -m 644 /tmp/sb_push/skybreaker_server.pck /opt/skybreaker/bin/ &&
  sudo install -o skybreaker -g skybreaker -m 644 /tmp/sb_push/lobby.js /opt/skybreaker/lobby/ &&
  rm -rf /tmp/sb_push && sudo systemctl restart skybreaker-lobby && sleep 2 && curl -s http://127.0.0.1:24600/health'
echo
