# Power Quest — Contexte projet (référence agent)

> **Usage** : lire ce fichier en début de session (`@PROJECT_CONTEXT.md`).  
> **Réseau** : Web-only au lancement — voir **`docs/MULTIPLAYER_ARCHITECTURE.md`**.  
> Stack cible : **Nakama** (auth + lobby/matchmaking) + **Godot headless pool** (simulation, plusieurs matchs).  
> **Pas de P2P** ; clients Web en **WSS** vers le pool. Solo = 1 humain + 7 IA côté serveur.

---

## 1. Stack & config

| Élément | Valeur |
|--------|--------|
| Moteur | Godot **4.6** (`config/features`: Forward Plus) |
| Rendu | `gl_compatibility` (desktop + mobile) |
| Physique 3D | Jolt (peu utilisé — jeu **2D**) |
| Viewport | 1680×945, stretch `viewport` |
| Nom projet | `2proj` (`project.godot`) |

### Autoloads (`project.godot`)

| Nom | Script | Rôle |
|-----|--------|------|
| `MapSession` | `scripts/map_session.gd` | `active_map_index` : 1 = Undead-Land, 2 = Cave-Land |
| `Economie` | `scripts/economie.gd` | Or joueur local, signal `argent_modifie` |
| `GameManager` | `scripts/game_manager.gd` | Timer global 30s, assignation camps, victoire/défaite |
| `IAManager` | `scripts/ia_manager.gd` | IA ennemie (équipe 1) |
| `Sound` | `scenes/sound/sounds.tscn` | `play_menu1()`, `play_menu2()` |
| `ScreenAdapter` | `scripts/screen_adapter.gd` | Redimensionne/centre la fenêtre |

---

## 2. Arborescence utile

```
Power_Quest/
├── project.godot
├── PROJECT_CONTEXT.md          ← ce fichier
├── assets/                     # sprites, sons, tilesets sources
├── Tilesets/                   # .tres tilesets (map1, map2, road, bridges…)
├── scenes/
│   ├── jeu/                    # Main, map_select_menu
│   ├── camp/                   # prefabs camps map1 / map2 / ports
│   ├── personnages/            # unités, projectiles, explosions
│   ├── camera/                 # ManagerRts
│   ├── ui/                     # production_ui, spell_ui, main_menu
│   └── sound/
└── scripts/                    # logique GDScript + resources/*.tres
```

---

## 3. Flux de scènes

```
menu_shell.tscn (entrée)
  ├─ Menu principal → Solo / Multijoueur / Profil / Maps / Settings
  ├─ Solo → MapSession (map + difficulté) → Main.tscn
  └─ Multijoueur → simulation UI (8/8, preview Map 2) — pas de lancement auto

Main.tscn
  ├─ Undead-Land OU Cave-Land (l’autre .free() selon MapSession.active_map_index)
  └─ main_game.gd → GameManager + IAManager
```

- **Entrée** : `run/main_scene` = `res://scenes/ui/menu_shell.tscn`
- **Navigation menus** : `scripts/ui/menu_shell.gd` + pages `scripts/ui/menu_page_*.gd`
- **Legacy** : `scenes/jeu/map_select_menu.tscn` (remplacé par menu Solo)

### Pages menu (UI basique, pas de backend)

| Page | Script | Notes |
|------|--------|-------|
| Principal | `menu_page_main.gd` | Quit → `get_tree().quit()` (désactivé sur Web) |
| Solo | `menu_page_solo.gd` | Difficulté + map → `Main.tscn` |
| Multijoueur | `menu_page_multiplayer.gd` | UI file (à brancher Nakama : 2–8 joueurs, timers 60s/5s) |
| Profil | `menu_page_profile.gd` | Données placeholder |
| Maps | `menu_page_maps.gd` | 3 maps + description / placeholder couleur |
| Settings | `menu_page_settings.gd` | Langue, résolution, sliders audio, liens |

---

## 4. Scène `Main.tscn` (structure)

Racine : `Node2D` + `main_game.gd`

| Enfant | Contenu |
|--------|---------|
| `Undead-Land` | Map 1 : TileMapLayers (water, ground, chemin, deco, collision) + ~20 camps + `NavigationRegion2D` |
| `Cave-Land` | Map 2 : layers (water, road, bridges, cloud…) + camps map2 + `Nav_water` + `Nav_ground` |
| `ProductionUI` | `scenes/ui/production_ui.tscn` |
| `SpellUI` | `scenes/ui/spell_ui.tscn` |
| `ManagerRts` | `scenes/camera/manager_rts.tscn` — groupe `manager_rts` |

**Fichier énorme** : éditer les camps/maps de préférence dans l’éditeur Godot, pas en diff texte brut.

### Camps instanciés

- **Map 1** : prefab type `camp_nv1.tscn` (script `camp_nv1.gd` → niveau 1)
- **Map 2** : `camp_nv1_map2.tscn` etc., `variante_visuelle_camp = "map2"`, `utiliser_overlays_visuels_niveau` souvent `false`

### Ports (camps spéciaux)

- `scenes/camp/map1/port/`, `scenes/camp/map2/port2/` — scripts `camp_nv1.gd` en général

---

## 5. Modèle de jeu (local, 1 humain vs IA)

### Équipes (`equipe` int / enum `Proprietaire`)

| Valeur | Nom | Rôle actuel |
|--------|-----|-------------|
| `0` | JOUEUR | Humain, or via `Economie`, sélection RTS |
| `1` | ENNEMI | IA (`IAManager`), or interne `or_ia` |
| `2` | NEUTRE | Camps non assignés au départ |

`GameManager._assigner_camps_initial()` : shuffle camps, répartit ~25 % équipe 0, ~25 % équipe 1, reste neutre.

**Victoire** : plus aucun camp équipe 1 → `VICTOIRE` ; plus aucun camp équipe 0 → `DEFAITE`.

### Groupes Godot

| Groupe | Membres |
|--------|---------|
| `camps` | Tous les camps (`camp.gd` `_ready`) |
| `soldats` | Unités + gardiens **équipe 0** |
| `ennemis` | Unités **équipe 1** (et pas dans `soldats`) |
| `manager_rts` | `ManagerRts` |

### Cycle global (`GameManager`)

- Toutes les **30 s** : +100 or joueur (`bonus_or`), renforts infanterie sur **un** camp joueur (`recevoir_renforts(2)`).
- IA : même timer → `or_ia += bonus_or + revenus camps × temps_cycle`.

---

## 6. Scripts — inventaire

### Cœur gameplay

| Fichier | Rôle |
|---------|------|
| `scripts/camp.gd` | **Classe de base** camps : production, capture, gardien, upgrade, revenus |
| `scripts/camp_nv1/2/3.gd` | `extends camp.gd`, fixe `niveau_camp` puis `super._ready()` |
| `scripts/game_manager.gd` | Timer, assignation, fin de partie |
| `scripts/ia_manager.gd` | Production + ordres attaque (profils AGRESSIF / STRATEGIQUE / EPARPILLE) |
| `scripts/economie.gd` | `argent`, `ajouter_argent`, `retrancher_argent` |
| `scripts/map_session.gd` | Index map active |

### Unités & combat

| Fichier | Rôle |
|---------|------|
| `scenes/personnages/player/player.gd` | **Script unique** presque toutes les unités (`CharacterBody2D`) : déplacement, attaque, sorts, gardien |
| `scripts/projectile.gd` | Projectiles génériques |
| `scripts/range_projectile.gd` | Flèches / projectiles distance |
| `scripts/range_projectile_land.gd` | Projectile sol range (feu) |

### UI & input

| Fichier | Rôle |
|---------|------|
| `scenes/camera/manager_rts.gd` | Caméra ZQSD, zoom, box select, clic camp, clic droit move/attack, touche **E** = sort |
| `scripts/production_ui.gd` | Panel production + upgrade (camps `equipe == 0` uniquement) |
| `scripts/spell_ui.gd` | Boutons sorts healer / support / mortar (sélection `soldats` équipe 0) |
| `scenes/jeu/map_select_menu.gd` | Choix map 1/2 |
| `scenes/jeu/main_game.gd` | Active une map, relance init managers |

### Ressources stats

| Fichier | Rôle |
|---------|------|
| `scripts/resources/unite_stats.gd` | `class_name UniteStats` — prix, hp, vitesse, dégâts, portée, type |
| `scripts/resources/{type}/{type}-{1,2,3}.tres` | Stats par type et niveau |

---

## 7. Camps — API importante (`camp.gd`)

- **Production joueur** : `demander_production(id)` — ids UI :
  - `0` infanterie, `1` range, `2` heavy, `3` support, `4` healer, `5` anti_armor, `6` mortar
- **IA** : manipule directement `file_production`, `temps_restant`, `or_ia`
- **Capture** : `recevoir_degats`, mort gardien → `_etre_capture_par_equipe`
- **Upgrade** : `ameliorer_camp()`, niveaux 1→3 (revenu, hp, vitesse prod)
- **Signaux** : `production_maj(taille, progression)`, `camp_upgrade(nouveau_niveau)`
- **Niveau visuel** : `niveau_camp`, `variante_visuelle_camp` (`"map1"` / `"map2"`)

Spawn unités : parent = **parent du camp** (souvent couche map), position `Marker2D` + offset aléatoire.

---

## 8. Unités (`player.gd`)

- Propriétés : `stats: UniteStats`, `equipe`, `hp_actuels`, `cible_attaque`, mode `est_gardien_camp`
- Méthodes clés : `aller_vers`, `attaquer_cible`, `recevoir_degats`, `lancer_sort`, `set_selection`, `configurer_mode_gardien`
- Types spéciaux : mortar (explosions, cooldowns), range (projectiles), healer/support (sorts via `SpellUI`)
- Signal : `mort_par_tueur(tueur, tueur_equipe)`

### Scènes par famille (`scenes/personnages/`)

| Dossier | Fichiers | Notes |
|---------|----------|-------|
| `infantry/` | `infantry-1..3.tscn` | |
| `range/` | `range-1..3`, projectiles | |
| `heavy/`, `support/`, `healer/` | nv1–3 | |
| `anti_armor/`, `mortar/` | nv1–3 + explosions | |
| `guardian/` | `gardien-1..3` | Gardiens de camp |
| `Water_*` | tank, range, transport nv1–3 | Variantes **eau** (map2 / nav) — même `player.gd` |

Prefab générique : `soldat.tscn` (legacy / test).

---

## 9. Assets

```
assets/
├── character/          # sprites par unité (nv1/nv2/nv3), explosions mortar, player
├── tilesets/           # Desert, Swamp, Road, Bridges, Cloud, map1…
├── objects/            # map1/, map2/ décorations animées
└── sounds/             # menu1.wav, menu2.wav
```

Convention sprites : dossiers `nv1`, `nv2`, `nv3` avec `idle`, `run`, `attack`, `death` selon l’unité.

---

## 10. Tilesets (`Tilesets/`)

| Fichier | Usage |
|---------|-------|
| `map1/map_1_tiles.tres` | Undead-Land |
| `map2/desert_tiles.tres` | Cave-Land |
| `Utils_obj/road.tres`, `bridges.tres`, `cloud.tres`, `Rock.tres` | Map 2 routes / ponts / nuages |

Layers typiques map2 : `road`, `bridges_back`, `bridges_front`, `Nav_water`, `Nav_ground`.

---

## 11. Multijoueur (cible — détail dans `docs/MULTIPLAYER_ARCHITECTURE.md`)

- **Nakama** : auth, file 2–8, timers (60 s reset, 5 s si 8), notification `match_ready`.
- **Game pool** (Godot headless) : plusieurs `MatchInstance`, simulation autoritaire.
- **Web** : export HTML5, connexion **WSS** (pas ENet, pas P2P mesh).
- **Solo en ligne** : 1 humain + 7 IA sur le serveur.
- **Sync** : commandes RPC (`cmd_produce`, `cmd_move`, …) ; IA seulement si `multiplayer.is_server()`.

---

## 12. Conventions code

- Langue : commentaires / prints souvent **français**
- `equipe` : `int` (0/1/2), enums miroir dans `camp.gd` et `player.gd`
- Vérifier `has_method` avant appels dynamiques (déjà fait pour `initialiser_partie`)
- Camps map2 : souvent pas d’overlays map1 (`utiliser_overlays_visuels_niveau = false`)

---

## 13. Fichiers volumineux / binaires (git)

- `scenes/jeu/Main.tscn` — très gros
- `power_quest_server_export/`, `web_server_export/` — exports (ne pas analyser pour la logique gameplay)
- `.godot/`, `export_presets.cfg` ignorés

---

*Dernière mise à jour : contexte gameplay local, branche `nouveau_test_serveur`, réseau non implémenté.*
