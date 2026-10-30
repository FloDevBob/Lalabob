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

### J1 — Moteur audio 🟡 code terminé, essai matériel à faire (branche `j1/moteur-audio`)
**Avancement** — étape 1/3 ✅ moteur + tests hors ligne · étape 2/3 ✅ branchement `ShowController` · étape 3/3 ✅ interface (grille cliquable, sortie, Tout arrêter). **Reste : l'essai sur le vrai Mac de régie** (check-list ci-dessous), puis fusion de la PR.
- `LalabobAudio` : implémentation AVAudioEngine de `AudioEngineControlling`.
  - Un `AVAudioPlayerNode` par pad actif, un `AVAudioMixerNode` par colonne (fader), un mixeur principal.
  - Lancer / relancer / pause / reprise / arrêter, boucle, élagage début–fin, fondus entrée / sortie.
  - Sons < 30 s préchargés en mémoire ; sons longs lus en flux.
  - « Tout arrêter » (Échap).
- Sélecteur de sortie audio dans la barre d'en-tête ; changement de sortie sans redémarrer ; survit au débranchement.
- Grille cliquable à la souris (mode Live) ; état de lecture visible sur les pads (lueur, barre de progression).
- **Terminé quand** : 16 sons simultanés sans craquement, déclenchement immédiat, tests de rendu hors ligne (fondus, élagage) verts.
- **Fait (étape 1)** : `AVAudioEngineController` (acteur), `ClipTiming`, `ClipRenderer` (élagage, fondus et gain « cuits » pour les sons < 30 s), `RetriggerAction`, `AudioOutputDevices` (CoreAudio), `SilentAudioEngine`. 32 tests verts (cible `LalabobAudioTests`, rendu hors ligne).
- **Fait (étape 3)** : `ControllerSession` (détecte le contrôleur, l'écoute, envoie `connectionMessages` puis les LED, traduit appuis et faders, se reconstruit au rebranchement), `LEDPlanner` (case vide éteinte, pad à sa teinte, son en lecture qui pulse, son en pause atténué ; seules les LED qui changent sont renvoyées), `ShowController.connectedController`, indicateur dans l'en-tête. Un appui sur le contrôleur joue toujours, même en mode Édition. Débrancher ne coupe aucun son (testé). 27 tests Engine verts avec un faux transport.
- **Essai matériel J2 (à cocher)** : ☐ Launchpad : mode Programmeur, 4 coins allumés au bon endroit, appui = bon son ☐ APC : idem + faders 1–8 bougent les colonnes de l'écran, le 9e ne fait rien ☐ les 16 teintes à côté de l'écran (ajuster `LaunchpadDriver.sevenBit` / palette APC) ☐ le son pulse sur la LED pendant la lecture ☐ débrancher / rebrancher en jouant : le son continue, les LED reviennent ☐ un autre logiciel écoute toujours l'APC (volume Apple Music) ☐ relever la réponse d'identité (octets famille) et les noms de ports réels, les noter dans `docs/hardware/`.
- **Limites connues J2** : pas de message de déconnexion propre à la fermeture de l'app (le Launchpad reste en mode Programmeur jusqu'au débranchement) ; les faders physiques « sautent » à la valeur de l'écran quand on change d'onglet (pas de prise en main progressive) ; relâchement des pads ignoré (utile au J3, comportement « maintenu ») ; `CoreMIDISession` sans test automatique.
- **Fait (étape 2)** : `ShowController` envoie ses commandes au moteur par une file unique (ordre garanti) ; mode Édition / Live (`press(at:)`), `stopAll`, `setColumnLevel` (borné 0…1, renvoyé à chaque changement d'onglet), `selectOutput` (mémorisée dans `UserDefaults`), état de lecture observable (`playback`), `loadTrialSounds()` (sons d'essai en attendant le glisser-déposer du J4). 12 tests verts (cible `LalabobEngineTests`, faux moteur).
- **Fait (étape 3)** : en-tête avec sélecteur de sortie, bascule Édition / Live, « Tout arrêter » (Échap), bouton provisoire « Sons d'essai » (charge `Application Support/Lalabob/Audio` du conteneur de l'app) ; pads avec contour + halo + barre de progression (lecture), contour atténué + icône pause (pause) ; fader de colonne provisoire (curseur horizontal, le fader vertical viendra au J5) ; menu contextuel Pause / Arrêter. `App/` ne dépend que d'Engine et Design (types audio réexportés par `LalabobEngine/LiveAudio.swift`).
- **Essai matériel J1 (à cocher)** : ☐ 16 sons simultanés sans craquement (Instruments si doute) ☐ déclenchement sans retard audible ☐ pause / reprise, relance, boucle, fondus, élagage (à régler dans `show.json` en attendant le J5) ☐ changement de sortie en cours de lecture ☐ débranchement de la sortie choisie : le son continue sur la sortie par défaut ☐ Échap coupe tout ☐ fader de colonne.
- **Choix / limites connus** : fondu de sortie ignoré pour les boucles ; sons longs lus en flux avec fondus par volume du lecteur (pas de test hors ligne) ; « Tout arrêter » coupe net (pas de fondu) ; reprise après changement de sortie implémentée mais à essayer sur le vrai matériel ; en rendu hors ligne un `play()` peut démarrer un bloc trop tard sans pause préalable (géré dans `renderOffline`) — à surveiller en temps réel (latence de déclenchement).
- **Note outillage (Xcode)** : après l'ajout d'un fichier source, `touch Packages/LalabobKit/Package.swift` force Xcode à relire le package (sinon « Cannot find … in scope »).
- **Note outillage** : `swift test` en terminal échoue (toolchain sans module Testing, cache bloqué par le bac à sable) → lancer les tests via Xcode (schéma `LalabobAudioTests`).

### J2 — Contrôleurs 🟡 code terminé, essai matériel à faire (branche `j2/controleurs`, empilée sur `j1/moteur-audio`)
**Avancement** — étape 1/3 ✅ détection · étape 2/3 ✅ session CoreMIDI · étape 3/3 ✅ appuis, faders, LED, reconnexion. **Reste : l'essai sur Launchpad et APC** (check-list ci-dessous).
- **Fait (étape 2)** : `UMP` / `UMPDecoder` (codec pur octets ⇄ paquets universels, SysEx découpé en 6 octets et reconstitué entre deux envois ; 15 tests), protocole `MIDITransport` (sources, destinations, écoute, envoi, changements), `CoreMIDISession` (acteur : client, port d'entrée UMP, port de sortie, envoi par `MIDISendEventList`). **`CoreMIDISession` n'a pas de test automatique** (il faut du MIDI réel) : à essayer avec un contrôleur branché ; les tests de l'orchestration utiliseront un faux transport.
- **Fait (étape 1)** : `ControllerModel.detect(portName:)`, `isControlPort(named:)` (Launchpad : port MIDI, pas DAW), `isConsistent(with:)` (fabricant Novation `00 20 29` / Akai `47`). Les octets « famille » de la réponse d'identité ne sont pas encore connus : à relever sur le matériel (journaliser la réponse), puis à ajouter ici et dans `docs/hardware/`.
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
