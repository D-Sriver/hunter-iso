# True Hunter

Roguelite d'action en 3D isométrique, dans un Néo-Tokyo cyberpunk façon anime des années 90.
Tu plonges dans un complexe généré au hasard pour voler une relique, puis tu dois t'enfuir
pendant que les hunters rivaux te traquent.

- Moteur : [Godot 4.7](https://godotengine.org/) (GDScript)
- Assets : Blender, générés par script (`blender/`)
- Cible : PC Windows, Steam, gratuit

## Lancer le jeu

Ouvre le dossier dans Godot 4.7 puis appuie sur F5. Au premier lancement, Godot importe les
modèles `.glb` du kit, ça prend quelques secondes.

| Action | Clavier | Manette |
|---|---|---|
| Se déplacer | ZQSD / WASD / flèches | stick gauche |
| Attaquer (assomme) | J ou clic gauche | X |
| Dash | Espace | A |
| Ouvrir un coffre / fuir | E | Y |
| Nouvelle run | R | Start |

## Régénérer les modèles

Tous les modèles viennent de `blender/kit.py` (géométrie) et `blender/textures.py` (textures
procédurales). Depuis la racine du dépôt :

```
blender --background --python blender/kit.py                 # exporte assets/kit/*.glb
blender --background --python blender/kit.py -- --preview    # + rendu d'une salle
blender --background --python blender/kit.py -- --lineup     # + rendu des six hunters
blender --background --python blender/kit.py -- --portrait   # + gros plan des visages
blender --background --python blender/kit.py -- --poses      # + poses clés des animations
```

Les rendus vont dans `docs/renders/`.

## Organisation

- `scripts/main.gd` : déroulé d'une run (relique, alerte, coffres, sorties, caméra, ambiance).
- `scripts/level_generator.gd` : plan du niveau en salles reliées par des couloirs.
- `scripts/level_builder.gd`, `scripts/decor.gd` : pose les pièces du kit sur ce plan.
- `scripts/kit.gd` : charge les `.glb` et leur applique le rendu anime (ombrage en deux tons,
  contour via `shaders/outline.gdshader`).
- `scripts/player.gd`, `scripts/rival.gd` : le joueur et les hunters rivaux (IA par personnalité).
- `scripts/hunter_animator.gd` : choisit l'animation d'un hunter (repos, course, dash, attaque,
  assommé), toutes faites dans `blender/kit.py`.
