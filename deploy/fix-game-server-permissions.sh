#!/bin/bash
# Sur le VPS après upload du binaire (scp) — évite systemd 203/EXEC
set -e
DEPLOY="${DEPLOY:-/root/deploy}"
BIN="$DEPLOY/power_quest_server.x86_64"

if [[ ! -f "$BIN" ]]; then
  echo "Manquant: $BIN"
  exit 1
fi

chmod 755 "$BIN"
file "$BIN"
ls -la "$BIN"

systemctl restart powerquest-game
sleep 2
systemctl is-active powerquest-game
ss -tlnp | grep 9080 || { echo "Port 9080 absent"; exit 1; }
echo "OK — serveur jeu actif"
