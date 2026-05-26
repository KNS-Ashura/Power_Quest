#!/bin/bash
# Diagnostic + rappels de fix pour 203/EXEC et Apache 8910→9080
# Usage sur le VPS : bash fix-vps-game-server.sh
set -euo pipefail

BIN="/root/deploy/power_quest_server.x86_64"
PCK="/root/deploy/power_quest_server.pck"
PORT=9080

echo "=== 1. Fichier binaire ==="
if [[ ! -f "$BIN" ]]; then
  echo "ERREUR: $BIN introuvable."
  echo "  → Recopie l'export Linux depuis Godot (preset Server) vers /root/deploy/"
  ls -la /root/deploy/ 2>/dev/null || true
  exit 1
fi
ls -la "$BIN" "$PCK" 2>/dev/null || ls -la "$BIN"
file "$BIN" || true

echo ""
echo "=== 2. Permissions + test manuel ==="
chmod +x "$BIN"
echo "Lancement test 3s (Ctrl+C si bloqué)..."
timeout 3 "$BIN" --headless -- --server --port "$PORT" 2>&1 || true

echo ""
echo "=== 3. Port en écoute ==="
ss -tlnp | grep "$PORT" || echo "(rien sur $PORT — normal si le test timeout a tué le process)"

echo ""
echo "=== 4. Apache ProxyPass /game (doit être 9080, PAS 8910) ==="
grep -rn "ProxyPass /game" /etc/apache2/ || true
echo ""
echo "Si tu vois 8910, corrige puis :"
echo "  sudo sed -i 's|ws://127.0.0.1:8910/|ws://127.0.0.1:9080/|g' /etc/apache2/sites-available/*.conf"
echo "  sudo apache2ctl configtest && sudo systemctl reload apache2"

echo ""
echo "=== 5. systemd ==="
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl restart powerquest-game"
echo "  systemctl status powerquest-game --no-pager"
echo "  curl -sI https://powerquest.robinmatelot.codes/game   # plus de 503"
