#!/usr/bin/env bash
# One-time setup of the Skybreaker co-op VM (Debian 12, x86_64). Run as root.
# Usage: setup_vm.sh <public-hostname>      e.g. 34-1-2-3.sslip.io
# Safe to run again. The signing key is NOT set here: put it in
# /etc/skybreaker/lobby.env (SB_SIG_KEY=...) by hand, the file is root-only.
set -euo pipefail
HOST="${1:?public hostname}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nodejs caddy rsync >/dev/null

id skybreaker >/dev/null 2>&1 || useradd --system --home /opt/skybreaker --shell /usr/sbin/nologin skybreaker
mkdir -p /opt/skybreaker/bin /opt/skybreaker/lobby /etc/skybreaker
chown -R skybreaker:skybreaker /opt/skybreaker

# 1 GB of memory is tight for two rooms: a swap file keeps a spike from killing a game.
if [ ! -f /swapfile ]; then
  fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

if [ ! -f /etc/skybreaker/lobby.env ]; then
  cat > /etc/skybreaker/lobby.env <<ENV
LOBBY_PORT=24600
PUBLIC_HOST=$HOST
GODOT=/opt/skybreaker/bin/skybreaker_server.x86_64
ROOM_EXPORTED=1
ROOM_PORT_MIN=24800
ROOM_PORT_MAX=24839
MAX_ROOMS=4
SB_SIG_KEY=
ENV
  chmod 600 /etc/skybreaker/lobby.env
fi

cat > /etc/systemd/system/skybreaker-lobby.service <<'UNIT'
[Unit]
Description=Skybreaker co-op lobby (starts one room process per game)
After=network-online.target
Wants=network-online.target

[Service]
User=skybreaker
WorkingDirectory=/opt/skybreaker/lobby
EnvironmentFile=/etc/skybreaker/lobby.env
ExecStart=/usr/bin/node /opt/skybreaker/lobby/lobby.js
Restart=always
RestartSec=3
MemoryMax=850M
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/opt/skybreaker
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

# HTTPS in front of the lobby (phones refuse plain http). The lobby port itself is not opened in the firewall.
cat > /etc/caddy/Caddyfile <<CADDY
$HOST {
	reverse_proxy 127.0.0.1:24600
}
CADDY

systemctl daemon-reload
systemctl enable -q skybreaker-lobby caddy
systemctl restart caddy
echo "setup done for $HOST. Next: push_build.sh, set SB_SIG_KEY, systemctl restart skybreaker-lobby"
