# Spectacle d'entraînement (`Entrainement.lalabob`)

Le spectacle qui accompagne le tutoriel : des sons d'ambiance et de bruitage de type cinéma, rangés pour servir tous
les modules.

## Licences : seulement du CC0

Les sons seront **redistribués tels quels** : dans le dépôt GitHub public du tutoriel et dans l'app. Il faut donc une
licence qui permet de redistribuer les fichiers bruts.

| Source | Utilisable ici ? | Pourquoi |
|---|---|---|
| **Freesound, filtre CC0** | ✅ **oui, source principale** | Domaine public : redistribution libre, aucun crédit obligatoire (on créditera quand même par courtoisie). La licence est fixée **son par son** : vérifier chaque fichier. |
| Freesound, CC BY | ⚠︎ possible | Redistribution permise avec crédit (auteur, lien, licence) dans `CREDITS.md`. À éviter si un équivalent CC0 existe. |
| Freesound, CC BY-NC | ❌ | Clause non commerciale : à écarter, même si la troupe ne vend rien. |
| Sonniss (paquets GDC) | ❌ | Libres d'usage dans un projet, mais pas de republication des fichiers bruts. |
| BBC Sound Effects (RemArc) | ❌ | Usage personnel, éducatif ou de recherche ; redistribution incertaine. |
| Pixabay | ❌ | Interdit de distribuer les sons « seuls », sans les avoir transformés. |

Règle de travail : pour chaque son retenu, noter dans `CREDITS.md` le titre, l'auteur, l'adresse Freesound, la licence
**le jour du téléchargement**, et les retouches faites (coupe, normalisation, boucle).

## Contenu

Sons choisis, avec liens et préparation : voir `sons-selection.md`.

### Grille 1 « Découverte » (modules 1 à 5)

| Colonne | Pads (en boucle ↻) | Modules |
|---|---|---|
| 1 Ambiances | Pluie ↻ · Vent dans les arbres ↻ · Forêt la nuit ↻ · Rue de ville ↻ · Café animé ↻ · Bord de mer ↻ | 1, 2, 5 |
| 2 Bruitages | Tonnerre · Porte qui claque · Pas sur parquet · Verre brisé · Coups de feu lointains · Téléphone ancien | 1, 2 |
| 3 Cinéma | Montée de tension · Coup de théâtre (impact grave) · Whoosh · Battements de cœur ↻ · Horloge ↻ | 2, 5 |
| 4 Public | Applaudissements · Rires · Murmures de salle ↻ · « Oh ! » de surprise | 2 |
| 5 Transitions | Cloche · Gong · Raté ! (petit jingle comique) | 2, 5 |
| 6 *vide* | Laissée vide pour le module 4 (déposer ses propres sons) | 4 |
| 7–8 Lumière | Vides : on y crée et appaire ses cues au module 6 | 6 |

### Grille 2 « L'orage » (module 2 : changer de grille sans couper le son)

Une petite scène complète : pluie forte ↻, vent qui hurle ↻, tonnerre proche, volet qui claque, chiens au loin, horloge ↻.

## Fabrication du spectacle

`Entrainement.lalabob` est **fabriqué, pas monté à la main**, par `generateur/` (petit paquet Swift qui utilise
`LalabobModel` : le fichier passe par `Show.validate()`, le même encodage que l'app, puis est relu comme à l'ouverture).
Titres, sous-titres, teintes par famille (Ambiances azur, Bruitages orange, Cinéma violet, Public rose, Transitions
ambre ; grille « L'orage » indigo et ciel), boucles et volumes des pads (au plus +4 dB) sont dans
`generateur/Sources/GenerateTrainingShow/main.swift`. Pour le refaire après un changement :

```bash
cd docs/tutoriel/generateur && swift run --build-system native -c release GenerateTrainingShow ../Entrainement.lalabob/Audio ../Entrainement.lalabob
```

Les sons viennent du spectacle lui-même (`Audio/`, lus avant d'être réécrits) ; après une nouvelle préparation des sons,
remplacer le premier argument par `../sons/prepares`. Le test `TrainingShowTests` vérifie que le module 1 y trouve ses pads.

(`--build-system native` : le système de compilation par défaut échoue dans le bac à sable de l'agent.)

## Préparation des fichiers

**Fait le 27/11/2026** : `sons/prepares/` (30 fichiers, 24 Mo, gardés en local : le spectacle les contient), refait à l'identique par
`python3 docs/tutoriel/sons/prepare_sons.py docs/tutoriel/sons/originaux docs/tutoriel/sons/prepares <dossier temporaire>`
(ffmpeg et `afconvert`). Les originaux (≈ 260 Mo) restent en local dans `sons/originaux/`, ignorés par git.
Crédits et retouches : `CREDITS.md`.

- Format : AAC 256 kb/s (`.m4a`), 48 kHz, stéréo ; ambiances de 22 s à 71 s, **bouclées sans clic** (longueur exacte à
  l'échantillon : le décalage de l'encodeur AAC est déclaré dans le fichier) ; bruitages courts.
- Niveau homogène : ambiances −20 LUFS, bruitages −16 LUFS, crête vraie ≤ −1 dBTP.
- Titres et sous-titres en français dans le spectacle, une teinte par famille de sons.
- Poids total visé : < 50 Mo (le spectacle est dans le dépôt et dans l'app).

## Mots-clés de recherche (Freesound, filtre CC0)

`rain loop`, `wind trees`, `forest night ambience`, `city street ambience`, `cafe ambience`, `ocean waves`,
`thunder`, `door slam`, `footsteps wood`, `glass break`, `gunshot distant`, `old phone ring`, `tension riser`,
`cinematic impact`, `whoosh`, `heartbeat`, `clock ticking`, `applause`, `crowd laugh`, `audience murmur`,
`crowd gasp`, `bell`, `gong`, `dog bark distant`, `shutter bang`.
