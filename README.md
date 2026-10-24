# Hunter Iso

Roguelite d'action en 3D isométrique, dans un Néo-Tokyo cyberpunk façon anime des années 90.
Tu plonges dans un labyrinthe généré au hasard pour voler une relique, puis tu dois t'enfuir
pendant que les hunters rivaux te traquent.

- Moteur : [Godot 4](https://godotengine.org/) (GDScript)
- Assets : Blender, via des scripts Python
- Cible : PC Windows, Steam, gratuit

## Lancer le prototype

1. Installe Godot 4.3 ou plus récent (version standard, pas besoin de la version .NET).
2. Dans Godot, clique sur **Importer**, choisis le fichier `project.godot` de ce dossier.
3. Appuie sur **F5** (ou le bouton ▶ en haut à droite).

Chaque lancement, et chaque appui sur **R**, génère un nouveau labyrinthe.

## Contrôles

| Action | Clavier (AZERTY / QWERTY) | Manette |
| --- | --- | --- |
| Bouger | ZQSD / WASD ou flèches | Stick gauche |
| Dash (esquive les coups) | Espace | A |
| Frapper (étourdit un rival) | J ou clic gauche | X |
| Ouvrir un coffre, fuir sans la relique | E (maintenir pour un coffre) | Y |
| Nouvelle run | R | Start |

## Ce que contient le prototype

- **Labyrinthe généré** : couloirs, quelques boucles et salles, 3 sorties sur les bords.
- **Relique** au point le plus éloigné du départ. La prendre déclenche une **alerte générale** :
  tout le monde est prévenu et un faisceau rouge révèle le porteur.
- **3 rivaux** qui cherchent eux aussi la relique, chacun avec sa réaction à l'alerte :
  - le **Traqueur** fonce sur le porteur ;
  - la **Sentinelle** garde la sortie la plus proche du porteur ;
  - l'**Opportuniste** suit de loin et frappe quand tu es à 1 PV.
- **Combat minimal** : un rival qui te touche retire 1 PV (3 PV au total) et te vole la relique.
  Frappe un rival pour l'étourdir : s'il porte la relique, elle tombe.
- **Coffres** dans les culs-de-sac : maintenir E pour les ouvrir, ça fait du bruit et attire les rivaux.
- **Fin de run** : sortie avec la relique (butin + 150 ¢), fuite sans la relique (butin seul) ou
  mort (rien). Les crédits sont sauvegardés entre les runs.

Tous les visuels sont des formes simples en attendant les modèles Blender.

## Structure

```
scenes/main.tscn          scène unique, tout est construit par code
scripts/main.gd           orchestration de la run (relique, alerte, coffres, sorties, fin)
scripts/maze_generator.gd génération du labyrinthe sur grille
scripts/level_builder.gd  sol, murs néon et sorties
scripts/player.gd         déplacement iso, dash, attaque
scripts/rival.gd          IA des rivaux et personnalités
scripts/chest.gd          coffres de butin
scripts/hud.gd            interface
scripts/input_setup.gd    touches et manette
scripts/save_data.gd      crédits conservés entre les runs
scripts/materials.gd      matériaux des placeholders
```
