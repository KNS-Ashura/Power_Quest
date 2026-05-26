#!/bin/bash
# Diagnostic + rappels pour powerquest-game (203/EXEC)
set -euo pipefail

BIN="/root/deploy/power_quest_server.x86_64"
DIR="/root/deploy"

echo "=== Fichiers dans $DIR ==="
ls -la "$DIR" || exit 1

echo ""
echo "=== Binaire attendu ==="
if [[ ! -f "$BIN" ]]; then
  echo "ERREUR: $BIN n'existe pas."
  echo "Copie l'export Linux depuis ton PC :"
  echo "  scp power_quest_server.x86_64 root@VPS:/root/deploy/"
  exit 1
fi

file "$BIN"
chmod +x "$BIN"

echo ""
echo "=== Test manuel (5 s) ==="
timeout 5 "$BIN" --headless -- --server --port 9080 || true

echo ""
echo "=== Service systemd ==="
systemctl cat powerquest-game.service 2>/dev/null || echo "Service absent"

echo ""
echo "=== Si 203/EXEC : vérifier ExecStart = $BIN ==="
echo "ExecStart=$BIN --headless -- --server --port 9080"
