# Plan d'implémentation de Lalabob

Copie de travail du plan (version d'origine : https://claude.ai/artifact/UZQWshXj9GUVkjtFMFBJcm).
**Ce fichier fait foi pour les agents de code** : le mettre à jour quand un jalon avance ou qu'une décision change.

## Objectif

Une app macOS native, modulaire, maintenable et sûre, qui reproduit la maquette (voir `docs/DESIGN.md`).
7 jalons ; chacun livre une app qui se lance, des tests verts et un essai sur le vrai matériel.

## Décisions prises (30 octobre 2026)

| Sujet | Décision |
| --- | --- |
| Mac de régie | macOS 26 et 27 → cible macOS 26 minimum |
| Outils | Xcode 27.1, Swift 6.4 (mode Swift 6 strict), XcodeGen |
| Signature | Locale (« Sign to Run Locally »), sans compte Apple. Pas de notarisation pour l'instant |
| Logiciel lumière | LightKey, via un port MIDI virtuel créé par Lalabob (« Lalabob Lumière ») |
| Sortie audio | Une seule, choisie dans la barre d'en-tête parmi les sorties branchées |
| Pré-écoute | Sur cette même sortie, désactivée en mode Spectacle |
| Faders physiques | APC mini mk2 : faders 1–8 → faders de colonne. Le 9e est ignoré (mappé dans un autre logiciel pour le volume d'Apple Music ; CoreMIDI permet à plusieurs apps de lire l'APC) |
| Nouvel appui sur un son | Relance depuis le début (option par pad : arrêter). Un son en pause reprend |
| Code | Dépôt GitHub privé FloDevBob/Lalabob, une branche + une PR par tâche |

## Jalons

### J0 — Fondations ✅ (compile et se lance le 30/10/2026)
- Projet XcodeGen, package `LalabobKit` (6 modules), modèle + validation, pilotes Launchpad / APC, fenêtre grille vide, tests, `CLAUDE.md`, ADR, skills.
- Reste : `make test` vert sur Mac, fusion de la PR.

### J1 — Moteur audio 🚧 (branche `j1/moteur-audio`)
**Avancement** — étape 1/3 ✅ moteur + tests hors ligne · étape 2 : branchement `ShowController` · étape 3 : interface (grille, sortie, Tout arrêter).
- `LalabobAudio` : implémentation AVAudioEngine de `AudioEngineControlling`.
  - Un `AVAudioPlayerNode` par pad actif, un `AVAudioMixerNode` par colonne (fader), un mixeur principal.
  - Lancer / relancer / pause / reprise / arrêter, boucle, élagage début–fin, fondus entrée / sortie.
  - Sons < 30 s préchargés en mémoire ; sons longs lus en flux.
  - « Tout arrêter » (Échap).
- Sélecteur de sortie audio dans la barre d'en-tête ; changement de sortie sans redémarrer ; survit au débranchement.
- Grille cliquable à la souris (mode Live) ; état de lecture visible sur les pads (lueur, barre de progression).
- **Terminé quand** : 16 sons simultanés sans craquement, déclenchement immédiat, tests de rendu hors ligne (fondus, élagage) verts.
- **Fait (étape 1)** : `AVAudioEngineController` (acteur), `ClipTiming`, `ClipRenderer` (élagage, fondus et gain « cuits » pour les sons < 30 s), `RetriggerAction`, `AudioOutputDevices` (CoreAudio), `SilentAudioEngine`. 32 tests verts (cible `LalabobAudioTests`, rendu hors ligne).
- **Choix / limites connus** : fondu de sortie ignoré pour les boucles ; sons longs lus en flux avec fondus par volume du lecteur (pas de test hors ligne) ; « Tout arrêter » coupe net (pas de fondu) ; reprise après changement de sortie implémentée mais à essayer sur le vrai matériel ; en rendu hors ligne un `play()` peut démarrer un bloc trop tard sans pause préalable (géré dans `renderOffline`) — à surveiller en temps réel (latence de déclenchement).
- **Note outillage** : `swift test` en terminal échoue (toolchain sans module Testing, cache bloqué par le bac à sable) → lancer les tests via Xcode (schéma `LalabobAudioTests`).

### J2 — Contrôleurs
- `LalabobMIDI` : session CoreMIDI dans un `actor` (sources, destinations, notifications de branchement).
- Détection automatique par requête d'identité → `ControllerModel` → pilote.
- Appui pad → `ShowController` → son ; LED synchronisées avec l'écran (RVB sur Launchpad, palette + canal sur APC).
- APC : faders 1–8 → niveaux de colonne.
- Reconnexion à chaud sans arrêter le son.
- **Terminé quand** : sur chaque contrôleur disponible, un appui joue le bon son, les LED ont les couleurs de l'écran, les faders de l'APC bougent ceux de l'écran, y compris après débranchement. Points ⚠︎ de `docs/hardware/` vérifiés.

### J3 — Lumière (LightKey)
- Port MIDI virtuel « Lalabob Lumière » (sortie seule, pas de boucle).
- Colonnes lumière : traduction note → message (`MIDIMessageSpec`) ; comportements impulsion / bascule / maintenu ; retour LED optionnel.
- Faders des colonnes lumière envoyés en CC.
- **Terminé quand** : LightKey voit le port, apprend les messages par son mapping MIDI et exécute les cues.

### J4 — Édition et spectacles · palier « utilisable en répétition »
- Document `.lalabob` (`FileDocument`, paquet : `show.json` + dossier `Audio/` où les sons sont copiés), `Show.validate()` à l'ouverture.
- Onglets de grilles (ajout, renommage, réordonnancement), raccourcis ⌘1…⌘9.
- Bibliothèque de fichiers à gauche (signets de portée sandbox), recherche, glisser-déposer vers les pads.
- Réagencement : glisser = déplacer / échanger, ⌥-glisser = dupliquer, ⌘X/C/V/D, ⌫, ⌘Z via `UndoManager`.
- Édition titre / sous-titre / couleur ; sauvegarde automatique.
- **Terminé quand** : la troupe monte un spectacle complet et le rouvre sur l'autre Mac.

### J5 — Inspecteur et design final
- Panneau du bas : nom du fichier, fondus, boucle, nouvel appui, forme d'onde (pics calculés avec Accelerate, cache disque), poignées d'élagage, tête de lecture, lecture / pause / stop.
- Palette 16 teintes, intensité LED, police Fredoka (logo), icônes Phosphor (Fill) + projecteur sur mesure, animations, accessibilité (VoiceOver, contrastes).
- **Terminé quand** : l'app est fidèle à la maquette, validée côte à côte.

### J6 — Fiabilisation et livraison · palier « prêt pour le spectacle »
- Mode Spectacle (édition verrouillée), tests de charge et d'endurance (3 h), scénarios de panne (contrôleur, carte son, LightKey), journal `OSLog`.
- Installation sur les deux Mac de régie, guide d'utilisation d'une page.
- **Terminé quand** : une répétition générale se déroule sans incident.

## Risques suivis

| Risque | Parade |
| --- | --- |
| Latence / craquements à forte charge | Test de charge dès J1, Instruments |
| Comportements MIDI non documentés (APC surtout) | Pilotes isolés, messages enregistrés, essais matériels tôt |
| Glisser-déposer SwiftUI limité (⌥ pour dupliquer) | Repli AppKit pour la grille si besoin |
| Format MIDI attendu par LightKey | Message de sortie configurable par pad, essai réel au J3 |
