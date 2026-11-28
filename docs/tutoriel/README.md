# Visite guidée de Lalabob

Une prise en main **rapide** (5 minutes, 17 bulles, 5 chapitres). La **copie de la fenêtre de Lalabob occupe tout
l'écran** et joue de vrais sons ; l'élément à utiliser est **mis en lumière** (le reste est assombri, un cadre ambré
pulse tant que le geste est à faire) et une **bulle le suit** : un titre, une ou deux phrases, le geste à faire, puis
ce qui vient de se passer. On fait le geste sur la copie, ou on clique **Suivant** : un curseur le fait à notre place.
L'accueil et la fin sont des cartes centrées. Une fine barre en haut montre les chapitres (clic = y aller).

Historique (27/11/2026) : une longue page à lire à côté de l'app, puis une colonne d'étapes à gauche de la copie
(modèle Impro Match) ont été abandonnées : trop longues, ou trop serrées pour manipuler la copie.

## Fichiers

- `visite/index.html` : la page (copie de la fenêtre + parcours), sans dépendance extérieure.
- `visite/sons.js` : 9 sons allégés en base64 (fabriqué par `sons/sons_visite.py`, 2 Mo), pour jouer sans réseau.
- `Entrainement.lalabob` : le spectacle d'entraînement (voir `spectacle-entrainement.md`).
- `sons/` : préparation des sons (`prepare_sons.py`), originaux et sons préparés gardés en local (hors git).
- `CREDITS.md`, `sons-selection.md` : sons CC0 de Freesound, auteurs et retouches.

## Parcours

| Chapitre | Bulles |
|---|---|
| 1 · Découvrir | Bienvenue (carte) · La grille · Sous chaque colonne · En haut |
| 2 · Jouer | Lancer un son (double-clic sur Pluie) · Un son par-dessus (Tonnerre) · Pause (Espace) · Tout arrêter (Échap) |
| 3 · Régler | Le volume (fader) · Le filtre (potard) |
| 4 · La lumière | Allumer les projecteurs (Plein feu) · L'intensité (fader) · Éteindre · Le contrôleur |
| 5 · Préparer | Le cadenas · Ajouter un son (glisser de la bibliothèque) · C'est parti (carte) |

Le chapitre lumière montre, dans la bulle, une petite **scène** : un projecteur par lumière, dont le faisceau suit
l'état (allumée / éteinte) et l'intensité. Vocabulaire : `docs/LEXIQUE.md` (lumière, projecteurs, relier, intensité ;
jamais cue ni LightKey dans la visite).

Seuls 9 pads son de la copie ont un son (Pluie, Vent, Tonnerre, Porte, Verre, Applaudissements, Rires, Cloche, Raté) ;
les autres jouent en silence, avec un message. Les 5 pads lumière de la copie (Plein feu, Douche bleue, Contre rouge,
Salle, Noir) n'existent que dans la visite.

## Dans l'app

- **Aide ▸ Visite guidée** : fenêtre qui affiche `visite/index.html` hors ligne (`App/TourView.swift`, reprise
  d'Impro Match). Proposée aussi une fois, à l'ouverture du premier spectacle. ⌘L agit sur le cadenas de la copie.
- La dernière étape, **Essayer maintenant**, ferme la visite et ouvre une copie neuve du spectacle d'entraînement.
- **Aide ▸ Ouvrir le spectacle d'entraînement** fait la même chose, sans la visite.
- `project.yml` copie `docs/tutoriel/visite` (dossier « visite ») et `docs/tutoriel/Entrainement.lalabob` dans l'app.

## Essayer la page dans un navigateur

```bash
cd docs/tutoriel/visite && python3 -m http.server 8765
```

puis ouvrir http://127.0.0.1:8765/. Hors de l'app, la dernière étape propose « Recommencer la visite » au lieu
d'« Essayer maintenant ».

## Quand l'interface change

La copie suit la vraie fenêtre (capture du 27/11/2026, fenêtre 1320 × 752, spectacle d'entraînement) : en-tête, pads,
cartes de volume, panneau du bas, bibliothèque. Après un changement visible de Lalabob, refaire une capture et
mettre la copie d'accord.

## Publication en ligne

À faire : comme Impro Match, un petit dépôt public qui ne contient que `visite/` (le dépôt de l'app reste privé),
publié avec GitHub Pages.
