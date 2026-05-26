# Export serveur Linux — éviter les erreurs au démarrage

## Erreurs GDExtension (discord, git-plugin)

Au lancement tu peux voir :

```text
GDExtension dynamic library not found: res://addons/discord_social_sdk/...
GDExtension dynamic library not found: res://addons/godot-git-plugin/...
```

Ce sont des **addons éditeur**, inutiles sur le serveur headless. Ils ne bloquent pas toujours le jeu, mais alourdissent l’export.

### Dans Godot — preset export **Linux serveur**

**Projet → Exporter → Linux → onglet Ressources → Exclure :**

```
addons/discord_social_sdk
addons/godot-git-plugin
```

Ou désactive ces plugins dans **Projet → Paramètres du projet → Plugins** avant d’exporter le serveur.

Puis **ré-exporter** et recopier sur le VPS :

- `power_quest_server.x86_64`
- `power_quest_server.pck` (si fichier séparé — **obligatoire** dans `/root/deploy/` à côté du binaire)

---

## Erreur WebSocket port 9080 (code 22)

Message :

```text
Impossible de démarrer le WebSocket sur le port 9080 (erreur 22)
```

**Cause la plus fréquente : le port 9080 est déjà pris** (ancien processus, systemd qui redémarre en boucle).

### Sur le VPS

```bash
sudo systemctl stop powerquest-game
sleep 2
sudo fuser -k 9080/tcp 2>/dev/null || true
ss -tlnp | grep 9080
# (rien ne doit s'afficher)

cd /root/deploy
./power_quest_server.x86_64 --headless -- --server --port 9080
```

Tu dois voir : `[GameServer] OK — écoute sur le port 9080`

Puis :

```bash
sudo systemctl start powerquest-game
```

---

## Fichiers requis dans `/root/deploy/`

```bash
ls -la /root/deploy/
```

Minimum :

| Fichier | Rôle |
|---------|------|
| `power_quest_server.x86_64` | Binaire (chmod +x) |
| `power_quest_server.pck` | Données du jeu (si export en 2 fichiers) |

Sans le `.pck`, le binaire peut démarrer mais se comporter bizarrement.
