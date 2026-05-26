# Power Quest — Reprise de session (à coller sur l’autre PC)

> **Usage** : ouvre ce fichier sur ton autre machine et dis à Cursor :  
> « Lis `@docs/HANDOFF_SESSION.md` et continue le multijoueur Web. »

Dernière mise à jour : mai 2026 — branche travail réseau / VPS `vmi3253012`.

---

## 1. Contexte projet (résumé)

- Jeu **Godot 4.6** — RTS, camps, unités, 2 maps.
- **Web-only** au lancement (navigateur).
- **Solo** (futur) : 1 humain + 7 IA sur serveur.
- **Multi** : matchmaking 2–8 joueurs (timers 60 s / reset / 5 s à 8 = pas encore codés).
- **Nakama** = auth + file d’attente ; **Godot headless** = simulation (pas P2P).
- Docs détaillées : `PROJECT_CONTEXT.md`, `docs/MULTIPLAYER_ARCHITECTURE.md`, `docs/SERVER_SETUP.md`.

---

## 2. Où on en est — VALIDÉ

### Serveur de jeu Godot — OK

- Binaire sur le VPS : **`/root/deploy/power_quest_server.x86_64`**
- Test manuel réussi :

```bash
cd /root/deploy
./power_quest_server.x86_64 --headless -- --server --port 9080
```

Sortie attendue (obtenue) :

```text
[GameServer] Scène serveur chargée (game_server_main.gd).
[GameServer] Port demandé : 9080 (args user: ["--server", "--port", "9080"])
[GameServer] OK — écoute sur le port 9080, en attente de 2+ joueurs.
```

- Port ouvert : `ss -tlnp | grep 9080` → `LISTEN *:9080 ... power_quest_ser`
- **systemd** `powerquest-game.service` fonctionne si `ExecStart` contient **`--server`**.

### Service systemd correct

Fichier : `/etc/systemd/system/powerquest-game.service`

```ini
[Service]
Type=simple
WorkingDirectory=/root/deploy
Environment=GODOT_SILENCE_ROOT_WARNING=1
ExecStart=/root/deploy/power_quest_server.x86_64 --headless -- --server --port 9080
Restart=on-failure
RestartSec=5
```

Commandes utiles :

```bash
sudo systemctl restart powerquest-game
systemctl status powerquest-game --no-pager
ss -tlnp | grep 9080
journalctl -u powerquest-game -f
```

### Problèmes déjà résolus

| Problème | Cause | Fix |
|----------|--------|-----|
| `203/EXEC` | Mauvais chemin (`/opt/powerquest/game_server` inexistant) | Chemin réel `/root/deploy/power_quest_server.x86_64` |
| Service `active` mais pas de port 9080 | Manquait `--server` dans `ExecStart` | Ajouter `--server` après `--` |
| Vieux export | Binaire sans `ServerMode` / `game_server_main` | Ré-exporter depuis le PC avec projet à jour |

---

## 3. Blocage « Connexion WebSocket… » (dépannage)

Écran : file OK, puis texte **Connexion WebSocket…** sans suite.

| Cause | Vérification | Fix |
|--------|----------------|-----|
| Proxy Apache `/game` absent ou 503 | `curl -sI https://powerquest.robinmatelot.codes/game` | `ProxyPass /game ws://127.0.0.1:9080/` + `a2enmod proxy_wstunnel` |
| Serveur jeu arrêté | `ss -tlnp \| grep 9080` | `systemctl restart powerquest-game` |
| Timeout client (bug corrigé) | Réexport Web après fix `network_session.gd` | Utilise `Time.get_ticks_msec()` |
| 1 seul onglet | Après WS OK, message « 2e onglet » | Ouvrir 2e onglet Multijoueur |

Test Apache WebSocket (VPS) :

```bash
curl -sI -H "Connection: Upgrade" -H "Upgrade: websocket" https://powerquest.robinmatelot.codes/game
```

---

## 4. Pas encore fait / à confirmer sur le VPS

Cocher mentalement ce qui est fait :

- [ ] **Nakama** Docker : `cd ~/deploy && docker compose up -d` + `curl http://127.0.0.1:7350/healthcheck`
- [ ] Module lobby : logs Nakama → `Power Quest lobby module loaded`
- [ ] **Apache** sur `powerquest.robinmatelot.codes` (modèle `deploy/apache/powerquest-same-domain.conf.example`) :
  - `ProxyPass /v2` → Nakama `127.0.0.1:7360` (docker mappe 7360:7350)
  - `ProxyPass /game` → WebSocket `ws://127.0.0.1:9080/`
  - CORS un seul `Access-Control-Allow-Origin` (pas de doublon avec Nakama `*`)
- [ ] **Export Web** déployé sur `powerquest.robinmatelot.codes` (projet à jour)
- [ ] **Test 2 onglets** : Multijoueur → file → connexion WS → scène **Main**
- [ ] **`curl -sI https://powerquest…/game`** → pas **503** (sinon `systemctl restart powerquest-game`, voir `deploy/TROUBLESHOOTING_WEBSOCKET.md`)

---

## 4. Architecture (rappel court)

```
Navigateur (powerquest.robinmatelot.codes)
    → HTTPS auth/file : powerquest.../v2  (Apache → Nakama Docker :7360)
    → WSS partie      : powerquest.../game  (Apache → Godot :9080)
```

- MVP file Nakama : **lancement dès 2 joueurs** (`deploy/nakama/modules/lobby.lua`).
- Client : `scripts/network/network_session.gd` (HTTP Nakama + WebSocket jeu).
- Menu multi : `scripts/ui/menu_page_multiplayer.gd`.

---

## 5. Fichiers importants dans le repo

| Chemin | Rôle |
|--------|------|
| `deploy/docker-compose.yml` | Nakama + Postgres |
| `deploy/nakama/modules/lobby.js` | RPC `join_queue`, `leave_queue` |
| `deploy/powerquest-game.service.example` | Modèle systemd |
| `scripts/server/game_server_main.gd` | Serveur WebSocket + lance Main à 2 clients |
| `scripts/server/server_mode.gd` | Détecte `--server`, charge `game_server_main` |
| `scripts/network/network_config.gd` | URLs prod / dev (`PQ_DEV=1`) |
| `scripts/network/network_session.gd` | Auth Nakama + connexion jeu |
| `scenes/server/game_server_main.tscn` | Scène principale export **serveur** |
| `scenes/ui/menu_shell.tscn` | Entrée client Web |

---

## 6. Ce que tu dois redire à Cursor sur l’autre PC

Copie-colle ce bloc :

---

**Reprise Power Quest multijoueur Web**

- Projet Godot 4.6, multijoueur Web-only, Nakama + serveur Godot headless (pas P2P).
- **Serveur jeu OK sur VPS** : `/root/deploy/power_quest_server.x86_64`, systemd `powerquest-game`, `ExecStart` avec `--headless -- --server --port 9080`, port **9080** en écoute, logs `[GameServer] OK`.
- Domaines : `powerquest.robinmatelot.codes` (client Web + proxy `/v2` Nakama + `/game` WSS — même domaine = pas de CORS). Option `api.powerquest…` possible mais le client actuel utilise le domaine principal (`network_config.gd`).
- **Prochaine étape** : valider Nakama + Apache (proxy `/v2` et `/game`) + test 2 navigateurs Multijoueur jusqu’à Main.
- Fichiers de reprise : `@docs/HANDOFF_SESSION.md`, `@docs/SERVER_SETUP.md`, `@docs/MULTIPLAYER_ARCHITECTURE.md`, `@PROJECT_CONTEXT.md`.
- Timers matchmaking 60 s / reset / 5 s à 8 : pas encore implémentés (MVP = go à 2 joueurs).

---

## 7. Commandes de diagnostic à fournir si ça bloque

```bash
# Jeu
systemctl status powerquest-game --no-pager
ss -tlnp | grep 9080
journalctl -u powerquest-game -n 30 --no-pager

# Nakama
cd ~/deploy && docker compose ps
curl -s http://127.0.0.1:7350/healthcheck
curl -s https://api.powerquest.robinmatelot.codes/healthcheck

# Service file
cat /etc/systemd/system/powerquest-game.service
```

---

## 8. Init partie multijoueur (B→F, code PC)

- Autoload **`OnlineMatch`** : le serveur assigne les camps (`nb_camps / nb_joueurs`), RPC `rpc_match_player_setup` vers chaque client.
- **`MapSession.local_team`** + `is_local_team()` / `is_hostile_team()` : UI RTS, production, sorts adaptés au joueur 2.
- **`GameManager`** : plus de `shuffle()` en ligne ; victoire/défaite multi-joueurs.
- **`IAManager`** : désactivé si `is_online_match` ou serveur dédié.
- **Prochaine étape (G)** : commandes via serveur (`cmd_produce`, `cmd_move`, …) — sinon désync dès un clic.

**Déployer** : réexport **Web client** + binaire **serveur** Linux, `lobby.lua` inchangé pour cette étape.

---

## 9. Correctifs code (session reprise PC)

| Problème | Fix |
|----------|-----|
| Joueur 1 reste en file après join du joueur 2 | `lobby.lua` : `pending_match` par `user_id` ; `queue_status` renvoie `matched` aux deux |
| RPC partie avant changement de scène | `game_server_main.gd` : `rpc_begin_online_match` puis `await` 1 frame puis `Main` |
| Comptage peers trop tôt | `call_deferred("_try_start_match")` à la connexion |
| Apache exemple mauvais port jeu | `8910` → `9080` dans les `.example` |
| CORS / domaines | Client = `powerquest…` + `/v2` + `/game` ; voir `deploy/apache/powerquest-same-domain.conf.example` |

**Sur le VPS après pull** : `docker compose restart nakama` (recharge `lobby.lua`) + réexport Web si scripts client changés + binaire serveur si `game_server_main.gd` changé.

---

## 10. Dernière réponse agent (état serveur validé)

Le serveur de jeu est **opérationnel** :

- Test manuel : `[GameServer] OK — écoute sur le port 9080`
- `ss` : `LISTEN *:9080 ... power_quest_ser`
- Les redémarrages rapides dans `journalctl` = plusieurs `systemctl restart`, pas un crash si le port reste ouvert.

**Suite recommandée :**

1. Vérifier `ExecStart` contient bien `--server`
2. `systemctl status` → `active (running)`
3. Nakama + Apache + export Web
4. Test 2 onglets Multijoueur

**Sécurité (plus tard)** : ne pas tourner en `root` ; utilisateur dédié + `/opt/powerquest`.

---

## 11. Export Godot (rappel PC)

**Serveur Linux** : scène principale `res://scenes/server/game_server_main.tscn` **ou** `menu_shell` + `--server` (avec `ServerMode` autoload). Recopier `.x86_64` (+ `.pck` si séparé) vers `/root/deploy/`.

**Web client** : scène principale `res://scenes/ui/menu_shell.tscn` → déployer sur `powerquest.robinmatelot.codes`.

**Dev local** : `PQ_DEV=1` → Nakama `127.0.0.1:7350`, jeu `ws://127.0.0.1:9080`.

---

*Fichier généré pour continuité entre machines — mettre à jour après chaque grosse étape (Nakama OK, test 2 joueurs OK, etc.).*
