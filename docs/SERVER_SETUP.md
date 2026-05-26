# Installation serveur — MVP « 1 partie qui se lance »

## « Daemon multi-salles », c’est quoi ? (pas pour tout de suite)

| Terme | Signification simple |
|--------|----------------------|
| **1 processus = 1 partie** | Chaque match lance un binaire Godot séparé. Pour 2 parties en parallèle → 2 processus. **C’est le plus simple pour commencer.** |
| **Daemon multi-salles** | **Un seul** programme Godot tourne en permanence et gère **plusieurs** parties en interne (salles A, B, C…). Moins de RAM, plus complexe à coder. |

**Pour l’instant** : objectif = **1 partie complète** avec **1 serveur de jeu** (un seul « salon »). Le multi-salles viendra quand 2 matchs simultanés seront stables.

---

## Vue d’ensemble MVP

```
[Navigateur] ──HTTPS──► powerquest.robinmatelot.codes (fichiers .html/.pck)
      │
      ├──► …/v2  ──► Docker Nakama :7360 (file 2 joueurs min, même domaine = CORS OK)
      │
      └──► …/game ──► Godot headless :9080 (WebSocket, la vraie partie)
```

Modèle Apache : `deploy/apache/powerquest-same-domain.conf.example`

1. Le joueur ouvre le site Web.
2. Auth Nakama (device).
3. **Multijoueur** → RPC `join_queue` → dès **2 joueurs** en file, Nakama renvoie `game_ws_url`.
4. Les 2 clients se connectent en WebSocket au **serveur Godot**.
5. Quand 2 peers sont connectés, le serveur charge `Main.tscn` → **partie lancée**.

---

## Étape 1 — Nakama sur Ubuntu (Docker)

Sur le VPS :

```bash
cd /chemin/vers/Power_Quest/deploy
chmod +x install-on-ubuntu.sh
export GAME_WS_URL="wss://api.powerquest.robinmatelot.codes/game"
./install-on-ubuntu.sh
```

Vérifier :

```bash
curl http://127.0.0.1:7360/healthcheck
docker compose logs -f nakama
```

> **Ports** : le compose expose Nakama sur **7360** (hôte), pas 7350, pour éviter un conflit si un autre service utilise déjà 7350.

**Important** : change `nakama_local_change_me` dans `docker-compose.yml` avant la prod.

### Apache — proxy Nakama (`api.powerquest…`)

Fichier modèle : **`deploy/apache/api-powerquest-cors.conf.example`**

```apache
# Healthcheck : /healthcheck (PAS /v2/healthcheck)
ProxyPass /healthcheck http://127.0.0.1:7360/healthcheck
ProxyPassReverse /healthcheck http://127.0.0.1:7360/healthcheck

<Location /v2>
    ProxyPass http://127.0.0.1:7360/v2
    ProxyPassReverse http://127.0.0.1:7360/v2

    # Obligatoire : enlever le CORS de Nakama (souvent "*") avant d'en mettre un seul
    Header always unset Access-Control-Allow-Origin
    Header always unset Access-Control-Allow-Methods
    Header always unset Access-Control-Allow-Headers

    Header always set Access-Control-Allow-Origin "https://powerquest.robinmatelot.codes"
    Header always set Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
    Header always set Access-Control-Allow-Headers "Authorization, Content-Type, Accept"

    RewriteEngine On
    RewriteCond %{REQUEST_METHOD} =OPTIONS
    RewriteRule ^ - [R=204,L]
</Location>
```

#### Erreur CORS fréquente (Multijoueur)

Chrome : `Access-Control-Allow-Origin header contains multiple values 'https://powerquest..., *'`

→ Apache **et** Nakama envoient chacun un header. **Supprime** les lignes `Header set Access-Control-*` **en dehors** de `<Location /v2>`, et garde le bloc `unset` + **un seul** `set` ci-dessus.

Puis : `sudo apache2ctl configtest && sudo systemctl reload apache2`

Le client Godot utilise `https://powerquest.robinmatelot.codes` pour `/v2` et `wss://…/game` (voir `scripts/network/network_config.gd`).

Test public :

```bash
curl https://api.powerquest.robinmatelot.codes/healthcheck
```

Réponse attendue : JSON avec `"status":"ok"` (ou similaire), **pas** `"code":5,"message":"Not Found"`.

> Si tu vois `Not Found` sur `/v2/healthcheck` : c'est normal, cette URL n'existe pas. Utilise `/healthcheck` sans le préfixe `/v2`.

---

## Étape 2 — Serveur de jeu Godot (headless)

### Export (important)

Le binaire serveur doit être **recompilé après chaque changement** des scripts réseau.

Dans Godot : **Projet → Exporter → Linux** (preset dédié « Server ») :

| Option | Valeur |
|--------|--------|
| Scène principale | `res://scenes/server/game_server_main.tscn` **ou** `menu_shell` + argument `--server` (les deux marchent avec `ServerMode`) |
| Ressources | Inclure `scripts/`, `scenes/server/`, `scenes/jeu/Main.tscn`, etc. |

Copie le nouveau `power_quest_server.x86_64` sur le VPS (`~/deploy/`).

### Erreur `rand_u64() not found`

Tu as un **vieux export** sur le serveur. Le code actuel n’utilise plus `rand_u64`. **Réexporte** depuis le PC et remplace le fichier sur le VPS.

### Lancer à la main (test)

```bash
chmod +x power_quest_server.x86_64
./power_quest_server.x86_64 --headless --server --port 9080
```

Réponse attendue :

```text
[GameServer] Écoute sur le port 9080 — en attente de 2+ joueurs.
```

**Pas** d’erreur `Parse Error` sur `network_session.gd`.

### Apache — proxy WebSocket jeu

```apache
ProxyPass /game ws://127.0.0.1:9080/
ProxyPassReverse /game ws://127.0.0.1:9080/
```

Les clients se connectent à `wss://api.powerquest.robinmatelot.codes/game`.

---

## Étape 3 — Export Web client

Export **HTML5/Web** vers `powerquest.robinmatelot.codes`.

Dans `scripts/network/network_config.gd`, vérifie :

- `nakama_host` = ton API HTTPS
- `game_ws_url` = ton WSS `/game`

---

## Test local (PC, avant le VPS)

Terminal 1 — Nakama :

```bash
cd deploy && docker compose up
```

Terminal 2 — Serveur Godot (éditeur ou export) :

```bash
godot --path . --headless res://scenes/server/game_server_main.tscn -- --server --port 9080
```

Variables pour le client (PowerShell) :

```powershell
$env:PQ_DEV="1"
```

Dans l’éditeur Godot, lance le projet (F5), Multijoueur × 2 instances ou 2 exports Web locaux.

---

## Étape 4 — Test « 1 partie » (production)

1. Nakama + Postgres UP (`docker compose ps`).
2. Serveur Godot headless sur 9080.
3. Ouvre **2 onglets** du jeu Web.
4. Multijoueur → les deux rejoignent la file.
5. À 2/8, match créé → connexion WS → chargement **Main**.

---

## Limites du MVP (normal)

- File : **lancement dès 2 joueurs** (pas encore timers 60 s / reset / 5 s à 8).
- **1 salon** de jeu (pas 2 parties parallèles).
- Sync RTS minimale : scène partagée ; commandes serveur à renforcer ensuite.
- Addon **nakama-godot** optionnel : le client utilise l’**API HTTP** Nakama (compatible Web).

---

## Prochaines étapes (après 1 partie OK)

1. Timers matchmaking dans `lobby.js`.
2. Solo 1 humain + 7 IA sur le même serveur.
3. 2e partie parallèle (2e processus ou daemon multi-salles).
