# Export Web — pont HTTP Nakama

## Pourquoi

En **éditeur Godot**, `HTTPRequest` fonctionne. En **export HTML5**, le même code reçoit parfois des corps
gzip/corrompus → JSON illisible, file `0/8`, erreurs `%` en boucle.

Le fichier **`pq_bridge.js`** utilise le **XHR du navigateur** (fiable) à la place de HTTPRequest WASM.

## Après chaque export Godot (Web)

1. Exporter vers `export/web/`
2. Lancer **une** de ces options :
   - `python deploy/push_exports.py` (patche + déploie sur le VPS)
   - ou copier `deploy/web/pq_bridge.js` → `export/web/`
   - et vérifier que `index.html` contient **avant** `index.js` :
     ```html
     <script src="pq_bridge.js"></script>
     <script src="index.js"></script>
     ```

## Apache (VPS)

Dans le vhost `/v2`, désactiver la compression JSON :

```apache
SetEnv no-gzip 1
SetEnv no-brotli 1
```

Voir `deploy/apache/powerquest-same-domain.conf.example`.
