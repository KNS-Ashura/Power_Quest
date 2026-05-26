# Audit réseau multijoueur — Power Quest

Date : mai 2026

## Résumé

| Zone | État avant | Action |
|------|------------|--------|
| Apache `/game` | Faux **502** si test `curl -I` (HEAD) | WSS OK en GET → **101** ; RewriteRule WebSocket |
| Apache Nakama | Port **7360** (docker map) | OK dans `000-default-le-ssl.conf` |
| systemd jeu | Parfois **203/EXEC**, sans `--server` | Service réécrit |
| Nakama lobby | Joueur 1 bloqué en file | **lobby.lua** + pending match |
| URL WebSocket | `/game` sans slash | **`/game/`** partout |
| Double lancement map | `_try_start_match` + RPC | RPC seul |
| 2 clients bloqués sur preview map | `change_scene` serveur **coupait** le WebSocket | Peer sur `NetworkSession` + RPC avant change_scene |
| Client équipes | Déjà `OnlineMatch` + `MapSession` | OK |

---

## Fichiers projet (corrigés)

| Fichier | Rôle |
|---------|------|
| `conf_api/000-default-le-ssl.conf` | Nakama 7360, WSS Rewrite → 9080 |
| `deploy/docker-compose.yml` | Ports 7360, `GAME_WS_URL` avec `/` |
| `deploy/nakama/modules/lobby.lua` | File + pending pour les 2 clients |
| `scripts/network/network_config.gd` | `wss://.../game/` |
| `scripts/network/network_session.gd` | WS URL payload, timeout ms, RPC |
| `scripts/network/online_match.gd` | Camps par joueur (serveur) |
| `scripts/server/game_server_main.gd` | Plus de double start |
| `deploy/powerquest-game.service.example` | `--server` obligatoire |

---

## Serveur VPS — à maintenir

```bash
systemctl status powerquest-game   # active
ss -tlnp | grep 9080              # LISTEN
ss -tlnp | grep 7360              # nakama
docker compose -f /root/deploy/docker-compose.yml ps
```

Test WSS :

```bash
# GET uniquement (curl -I / HEAD → faux 502)
curl -s -D - -o /dev/null \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  https://powerquest.robinmatelot.codes/game/
# Attendu : HTTP/1.1 101 Switching Protocols
```

---

## Après pull : actions obligatoires

1. **Réexport Web** (client) — scripts `network_*` changés  
2. **Réexport Linux serveur** — si `game_server_main.gd` changé  
3. Sur VPS : `docker compose restart nakama` (lobby.lua)  
4. `systemctl restart powerquest-game`  
5. Test **2 onglets** Multijoueur

---

## Non fait (prochaine itération)

- Timers matchmaking 60 s / reset / 5 s à 8  
- Solo 1 humain + 7 IA en ligne  
- Économie par joueur (RPC serveur)  
- Plusieurs parties parallèles sur un daemon  
