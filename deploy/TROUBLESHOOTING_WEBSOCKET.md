# WebSocket `/game` — dépannage

## Symptôme navigateur

```text
WebSocket connection to 'wss://powerquest.robinmatelot.codes/game' failed
```

## Test rapide (depuis ton PC)

```bash
# Ne pas utiliser curl -I (HEAD) : faux 502 avec Godot derrière Apache.
curl -s -D - -o /dev/null \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  https://powerquest.robinmatelot.codes/game/
```

| Réponse | Signification |
|---------|----------------|
| **503 Service Unavailable** | Apache proxy OK, mais **rien n’écoute** sur **9080** (souvent `powerquest-game` en crash ou binaire **sans chmod +x** → systemd **203/EXEC**) |
| **404 Not Found** | Pas de règle `/game` sur ce VirtualHost |
| **502** avec `curl -I` seul | **Faux positif** — retester en GET (ci-dessus) |
| **101 Switching Protocols** | WebSocket OK |

---

## Erreur systemd `status=203/EXEC`

`203/EXEC` = systemd **ne peut pas exécuter** `ExecStart` (pas un crash Godot).

| Cause | Vérification | Fix |
|--------|----------------|-----|
| Fichier absent | `ls -la /root/deploy/power_quest_server.x86_64` | Recopier l’export Linux depuis le PC |
| Pas exécutable | `ls -l` affiche `-rw-r--r--` (pas `x`) | `chmod 755 /root/deploy/power_quest_server.x86_64` puis `systemctl restart powerquest-game` |
| Mauvais format | `file …` → « ASCII » ou « PE32 » | Réexporter preset **Linux x86_64** (pas Windows) |
| `.pck` manquant | `ls power_quest_server.pck` | Copier le `.pck` à côté du `.x86_64` |

```bash
cd /root/deploy
ls -la power_quest_server.*
file power_quest_server.x86_64
chmod +x power_quest_server.x86_64
./power_quest_server.x86_64 --headless -- --server --port 9080
# Attendu : [GameServer] OK — écoute sur le port 9080
```

Script diagnostic : `bash deploy/fix-vps-game-server.sh`

**Arrêter la boucle de restart** le temps de corriger :

```bash
sudo systemctl stop powerquest-game
# corriger binaire + Apache, puis :
sudo systemctl start powerquest-game
```

---

## Apache : port **8910** au lieu de **9080**

Si `grep ProxyPass /game` affiche `8910`, le proxy pointe vers un port vide → **503**.

```bash
sudo sed -i 's|ws://127.0.0.1:8910/|ws://127.0.0.1:9080/|g' /etc/apache2/sites-available/*.conf
grep -r "ProxyPass /game" /etc/apache2/
sudo apache2ctl configtest && sudo systemctl reload apache2
```

Fichiers souvent concernés :

- `/etc/apache2/sites-available/000-default-le-ssl.conf`
- `/etc/apache2/sites-available/api.powerquest-le-ssl.conf`

---

## Sur le VPS (SSH)

### 1. Serveur de jeu actif sur 9080

```bash
systemctl status powerquest-game --no-pager
ss -tlnp | grep 9080
```

Attendu : `active (running)` et `LISTEN ... 9080 ... power_quest_ser`

Si inactif :

```bash
sudo systemctl restart powerquest-game
journalctl -u powerquest-game -n 40 --no-pager
```

Test local :

```bash
curl -sI http://127.0.0.1:9080/
# ou test manuel :
cd /root/deploy
./power_quest_server.x86_64 --headless -- --server --port 9080
# logs : [GameServer] OK — écoute sur le port 9080
```

### 2. Apache — proxy WebSocket vers **9080**

Dans le VirtualHost **HTTPS** de `powerquest.robinmatelot.codes` :

```apache
# Modules (une fois)
# sudo a2enmod proxy proxy_http proxy_wstunnel headers rewrite ssl

ProxyPass /game ws://127.0.0.1:9080/
ProxyPassReverse /game ws://127.0.0.1:9080/
```

Vérifier qu’il n’y a **pas** un ancien port (ex. `8910`) ailleurs dans le vhost.

```bash
grep -r "ProxyPass /game" /etc/apache2/
sudo apache2ctl configtest
sudo systemctl reload apache2
```

### 3. Re-test

```bash
curl -sI https://powerquest.robinmatelot.codes/game
```

Après correction : plus de 503 (souvent **400** ou **426** en GET simple sans Upgrade — c’est normal).

Test WebSocket (GET, pas `curl -I`) :

```bash
curl -s -D - -o /dev/null \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  https://powerquest.robinmatelot.codes/game/
```

Attendu : **HTTP/1.1 101 Switching Protocols**.

---

## Client Godot

`scripts/network/network_config.gd` :

```gdscript
game_ws_url = "wss://powerquest.robinmatelot.codes/game/"
```

Même domaine que le site Web (CORS + proxy `/v2` Nakama sur le même vhost).
