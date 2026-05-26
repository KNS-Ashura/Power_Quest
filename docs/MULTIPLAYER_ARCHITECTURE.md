# Power Quest — Architecture multijoueur (Web-only)

> Objectif : **100 % jouable dans le navigateur** au lancement.  
> Solo et multijoueur en ligne, **plusieurs parties simultanées** sur un service de jeu longue durée.  
> **Nakama** = auth + matchmaking + signalement ; **Godot headless** = simulation autoritaire RTS.

---

## 1. Décision : Nakama oui, mais pas pour simuler la RTS

| Composant | Outil | Pourquoi |
|-----------|--------|----------|
| Comptes / sessions | **Nakama** | Auth device/email, socket, présence |
| File d’attente 2–8 + timers | **Nakama Server Runtime** (TypeScript ou Go) | Règles custom (60 s / reset / 5 s à 8) |
| Simulation camps / unités / IA | **Godot headless** (pool longue durée) | Tu as déjà toute la logique en GDScript |
| Clients navigateur | **Export Web Godot** | Obligatoire |
| Transport jeu (8 joueurs) | **WebSocket (WSS)** vers le serveur Godot | **Pas** du P2P WebRTC mesh à 8 (ingérable pour une RTS) |

Nakama **ne remplace pas** le serveur de partie : son matchmaker natif ne gère pas « timer 60 s remis à zéro à chaque join ». On utilise un **module lobby custom** côté Nakama, qui **alloue** une partie sur le pool Godot quand les conditions sont remplies.

---

## 2. Règles produit (validées)

### Solo (en ligne)

- **1 humain + 7 IA** (équipes / camps selon design actuel).
- Toujours hébergé côté **serveur de jeu** (pas de simulation solo purement locale en prod).
- L’IA tourne **uniquement sur le serveur** (`IAManager` côté peer autoritaire).

### Multijoueur (matchmaking)

| Paramètre | Valeur |
|-----------|--------|
| Joueurs min | 2 |
| Joueurs max | 8 |
| À 2 joueurs | Timer **60 s** avant lancement |
| Chaque nouveau joueur | Timer **remis à 60 s** |
| À 8 joueurs | Lancement dans les **5 s** suivantes |
| Capacité serveur (exemple) | 16 joueurs en file → **2 parties × 8** en parallèle |

### Clients

- **Web uniquement** au lancement (pas de dépendance desktop pour jouer).

---

## 3. Schéma d’infrastructure (ton VPS)

```
Navigateur (powerquest.robinmatelot.codes)
    │  HTTPS — fichiers .html / .wasm / .pck
    │
    ├─► wss://api.powerquest.robinmatelot.codes/nakama
    │       Nakama (Docker) — auth, lobby, matchmaker custom
    │
    └─► wss://api.powerquest.robinmatelot.codes/game/{match_id}
            Apache reverse-proxy → Godot Game Pool (longue durée)
            Plusieurs MatchInstance en parallèle
```

| Domaine | Rôle |
|---------|------|
| `powerquest.…` | Static Web export (Apache) |
| `api.powerquest.…` | Nakama API + WebSocket Nakama + **proxy WSS** vers instances de jeu |
| Docker | Nakama + DB (Cockroach/Postgres) + Redis (recommandé) |
| Process / conteneur **game-pool** | Binaire Godot **headless** unique ou workers (voir §5) |

Le binaire Linux dans `/root` devient le **game pool**, pas le site web.

---

## 4. Pourquoi pas P2P / « anchored sur un joueur »

- En **Web**, ENet classique ne marche pas ; le P2P = WebRTC multi-peer.
- À **8 joueurs**, mesh = latence, désync et triche ; incompatible avec économie + 50+ unités.
- **Anchored** reste valide **si l’ancre = le serveur Godot** de la partie, pas un client.

→ **Serveur autoritaire par partie**, clients = entrées + affichage.

---

## 5. Pool de parties longue durée (plusieurs matchs simultanés)

### Option recommandée : **un daemon Godot headless multi-salles**

Un seul processus expose un routeur WebSocket :

- `MatchInstance` = sous-arbre ou scène dédiée avec son `Main` allégé.
- Chaque instance : max 8 peers, état isolé (camps, or, unités).
- Capacité : ex. `max_matches = floor(cpu_mem / cost_per_match)` ; file Nakama attend si pool plein.

### Option alternative : **un processus Godot par match**

- Orchestrateur (script systemd / petit service Go) spawn `power_quest_server --match-id=UUID --port=PORT`.
- Plus simple à isoler, plus lourd en RAM.
- Bon pour commencer le **MVP** (2 parties × 8 joueurs = 2 processus).

Pour 16 joueurs / 2 parties, les deux options fonctionnent ; préférer **multi-salles dans un daemon** à moyen terme.

---

## 6. Rôle détaillé de Nakama

### Ce que Nakama fait bien ici

1. **Auth** : `authenticate_device` / email (invité → compte).
2. **Socket** : présence, notifications lobby.
3. **Lobby custom** (Server Runtime) :
   - Entrée / sortie file multijoueur.
   - Stockage `queue_state` : liste `user_id`, `deadline_unix`, `count`.
   - Tick 1 s : broadcast `lobby_tick { players, seconds_left }`.
   - Quand `count >= 8` → `deadline = now + 5`.
   - Quand `count >= 2` et `now >= deadline` → **créer match**.
4. **Création match** : RPC `allocate_game_match(player_ids, mode, map_seed)` :
   - Appelle le **Game Pool** (HTTP interne ou socket admin).
   - Reçoit `{ match_id, ws_url, player_slot, team }`.
   - Envoie à chaque client via **match message** ou **notification**.

### Ce que Nakama ne fait pas (dans notre stack)

- Simuler `camp.gd` / `player.gd` (trop de logique Godot).
- Remplacer le timer 60 s/reset sans code custom.

### SDK client

- Addon **[nakama-godot](https://github.com/heroiclabs/nakama-godot)** (GDScript, Godot 4).
- Autoload `Nakama` + wrapper projet `NetworkSession` (à créer).

---

## 7. Flux utilisateur

### A. Lancement Web

1. Charge `powerquest.…` (export HTML5).
2. Auth Nakama (device id stocké `localStorage`).
3. Menu → Solo ou Multijoueur.

### B. Solo

1. RPC `find_solo_match` → pool crée **MatchInstance** solo (1 slot humain + 7 IA).
2. Client reçoit `ws_url` + `match_id`.
3. `WebSocketMultiplayerPeer` connecte au pool.
4. Serveur charge map, assigne camps, **IA côté serveur uniquement**.

### C. Multijoueur

1. Socket Nakama → RPC `join_ranked_queue`.
2. UI affiche compteur **N/8** + timer (events `lobby_tick`).
3. Quand Nakama notifie `match_ready` + `ws_url` :
   - Tous les clients connectent la **même** `MatchInstance`.
   - **Pas d’IAManager** pour les équipes humaines ; 2–8 humains répartis sur équipes 0/1 (règle à figer).
4. Serveur lance countdown chargement map puis simulation.

---

## 8. Synchronisation jeu (Godot, après connexion WS)

Modèle **commande → serveur → état** :

| Action client | RPC serveur | Effet |
|---------------|-------------|--------|
| Clic production | `cmd_produce(camp_id, unit_id)` | Valide or, file production |
| Clic droit | `cmd_move` / `cmd_attack` | Met à jour cible / pathfinding serveur |
| Upgrade camp | `cmd_upgrade_camp` | Valide coût |

Réplication :

- Phase 1 : RPC + variables sync sur camps + timer `GameManager`.
- Phase 2 : `MultiplayerSpawner` pour unités, sync position/HP (ancre = serveur).

Fréquence cible : **15–20 ticks/s** serveur pour la RTS.

---

## 9. Apache (`api.powerquest.…`)

Exemple de responsabilités :

```apache
# Nakama gRPC/HTTP + Socket
ProxyPass /nakama http://127.0.0.1:7350/
ProxyPass /ws nakama_ws://127.0.0.1:7350/

# Jeu (WebSocket upgrade)
ProxyPass /game/ ws://127.0.0.1:9080/
```

Adapter ports selon Docker Compose. **TLS obligatoire** (`wss://`) pour le Web export.

---

## 10. Docker Compose (cible minimale)

```yaml
services:
  nakama:
    image: heroiclabs/nakama:latest
    depends_on: [postgres]
    volumes:
      - ./nakama/data:/nakama/data
      - ./nakama/modules:/nakama/data/modules
  postgres:
    image: postgres:16
  game-pool:
    # image custom avec power_quest_server headless
    ports:
      - "9080:9080"
```

Le module `nakama/modules/lobby.ts` implémente les timers matchmaking.

---

## 11. Plan d’implémentation (ordre anti-boucle)

| Étape | Livrable | Test |
|-------|----------|------|
| **0** | Docker Nakama + module lobby vide + health | `curl api.../healthcheck` |
| **1** | Addon nakama-godot, auth device, connexion socket | Log « connected » dans Web export |
| **2** | RPC `join_ranked_queue` + timer 60/reset/5s/8 | 2 navigateurs voient le même timer |
| **3** | Game pool headless : 1 match, echo WS | Client Web reçoit ping |
| **4** | `allocate_match` Nakama → pool | Match créé, URL renvoyée aux clients |
| **5** | Solo 1+7 IA sur serveur | Partie solo jouable Web |
| **6** | Multijoueur 2–8 sans IA sur équipes humaines | 2 clients min |
| **7** | 2 matchs parallèles (16 joueurs) | Charge pool |
| **8** | Sync RTS (produce, move, combat) | Partie complète |

Ne pas brancher `Main.tscn` multijoueur avant l’étape 6.

---

## 12. Changements code projet (prévus)

| Fichier / zone | Changement |
|----------------|------------|
| `project.godot` | Autoloads `Nakama`, `NetworkSession`, `GamePoolClient` |
| `scripts/ui/menu_page_multiplayer.gd` | Remplacer simulation par events Nakama |
| `scripts/ui/menu_page_solo.gd` | RPC solo + connexion WS |
| `scripts/ia_manager.gd` | Exécuter **uniquement** si `multiplayer.is_server()` et mode solo/multi avec IA |
| `scripts/economie.gd` | Or **par joueur** (dict côté serveur) |
| `scripts/game_manager.gd` | Fin de partie / timer uniquement serveur |
| Export preset | **Web** + **Dedicated Server** (headless, pas de rendu) |
| `docs/` | Ce fichier + mise à jour `PROJECT_CONTEXT.md` |

---

## 13. Réponses directes

| Question | Réponse |
|----------|---------|
| Nakama utile ? | **Oui** pour auth, lobby, timers, allocation — **non** pour la simulation RTS |
| P2P vs serveur ? | **Serveur autoritaire** ; clients Web en **WSS** |
| Plusieurs parties en même temps ? | **Game pool** longue durée (multi-instance) |
| Solo en ligne ? | **1 humain + 7 IA** sur le même pool, pas de client local |
| Ancienne approche anchored ? | Garder l’idée **anchored = serveur de la partie** |

---

## 14. Prochaine action code (quand tu valides)

1. Ajouter `addons/nakama/` (release Godot 4 compatible).
2. `docker-compose.yml` + squelette `nakama/modules/lobby.ts`.
3. `scripts/network/network_session.gd` (auth + queue + callback `match_ready`).
4. Brancher `menu_page_multiplayer.gd` sur les events réels.

Prérequis serveur : URL exactes Nakama (`api.powerquest.…`), ports Docker, et si le pool Godot tourne déjà en headless sur le VPS.
