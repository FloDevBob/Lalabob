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
- **Fait (étape 2)** : `ShowController` envoie ses commandes au moteur par une file unique (ordre garanti) ; mode Édition / Live (`press(at:)`), `stopAll`, `setColumnLevel` (borné 0…1, renvoyé à chaque changement d'onglet), `selectOutput` (mémorisée dans `UserDefaults`), état de lecture observable (`playback`), `loadTrialSounds()` (sons d'essai en attendant le glisser-déposer du J4). 12 tests verts (cible `LalabobEngineTests`, faux moteur).
- **Fait (étape 3)** : en-tête avec sélecteur de sortie, bascule Édition / Live, « Tout arrêter » (Échap), bouton provisoire « Sons d'essai » (charge `Application Support/Lalabob/Audio` du conteneur de l'app) ; pads avec contour + halo + barre de progression (lecture), contour atténué + icône pause (pause) ; fader de colonne provisoire (curseur horizontal, le fader vertical viendra au J5) ; menu contextuel Pause / Arrêter. `App/` ne dépend que d'Engine et Design (types audio réexportés par `LalabobEngine/LiveAudio.swift`).
- **Essai matériel J1 (à cocher)** : ☐ 16 sons simultanés sans craquement (Instruments si doute) ☐ déclenchement sans retard audible ☐ pause / reprise, relance, boucle, fondus, élagage (à régler dans `show.json` en attendant le J5) ☐ changement de sortie en cours de lecture ☐ débranchement de la sortie choisie : le son continue sur la sortie par défaut ☐ Échap coupe tout ☐ fader de colonne.
- **Choix / limites connus** : fondu de sortie ignoré pour les boucles ; sons longs lus en flux avec fondus par volume du lecteur (pas de test hors ligne) ; « Tout arrêter » coupe net (pas de fondu) ; reprise après changement de sortie implémentée mais à essayer sur le vrai matériel ; en rendu hors ligne un `play()` peut démarrer un bloc trop tard sans pause préalable (géré dans `renderOffline`) — à surveiller en temps réel (latence de déclenchement).
- **Note outillage (Xcode)** : après l'ajout d'un fichier source, `touch Packages/LalabobKit/Package.swift` force Xcode à relire le package (sinon « Cannot find … in scope »).
- **Note outillage** : `swift test` en terminal échoue (toolchain sans module Testing, cache bloqué par le bac à sable) → lancer les tests via Xcode (schéma `LalabobAudioTests`).

### J2 — Contrôleurs 🟡 code terminé, essai matériel à faire (branche `j2/controleurs`, empilée sur `j1/moteur-audio`)
**Avancement** — étape 1/3 ✅ détection · étape 2/3 ✅ session CoreMIDI · étape 3/3 ✅ appuis, faders, LED, reconnexion. **Reste : l'essai sur Launchpad et APC** (check-list ci-dessous).
- **Fait (étape 3)** : `ControllerSession` (détecte le contrôleur, l'écoute, envoie `connectionMessages` puis les LED, traduit appuis et faders, se reconstruit au rebranchement), `LEDPlanner` (case vide éteinte, pad à sa teinte, son en lecture qui pulse, son en pause atténué ; seules les LED qui changent sont renvoyées), `ShowController.connectedController`, indicateur dans l'en-tête. Un appui sur le contrôleur joue toujours, même en mode Édition. Débrancher ne coupe aucun son (testé). 27 tests Engine verts avec un faux transport.
- **Essai matériel J2 (à cocher)** : ☐ Launchpad : mode Programmeur, 4 coins allumés au bon endroit, appui = bon son ☐ APC : idem + faders 1–8 bougent les colonnes de l'écran, le 9e ne fait rien ☐ les 16 teintes à côté de l'écran (ajuster `LaunchpadDriver.sevenBit` / palette APC) ☐ le son pulse sur la LED pendant la lecture ☐ débrancher / rebrancher en jouant : le son continue, les LED reviennent ☐ un autre logiciel écoute toujours l'APC (volume Apple Music) ☐ relever la réponse d'identité (octets famille) et les noms de ports réels, les noter dans `docs/hardware/`.
- **Limites connues J2** : pas de message de déconnexion propre à la fermeture de l'app (le Launchpad reste en mode Programmeur jusqu'au débranchement) ; les faders physiques « sautent » à la valeur de l'écran quand on change d'onglet (pas de prise en main progressive) ; relâchement des pads ignoré (utile au J3, comportement « maintenu ») ; `CoreMIDISession` sans test automatique.
- **Fait (étape 2)** : `UMP` / `UMPDecoder` (codec pur octets ⇄ paquets universels, SysEx découpé en 6 octets et reconstitué entre deux envois ; 15 tests), protocole `MIDITransport` (sources, destinations, écoute, envoi, changements), `CoreMIDISession` (acteur : client, port d'entrée UMP, port de sortie, envoi par `MIDISendEventList`). **`CoreMIDISession` n'a pas de test automatique** (il faut du MIDI réel) : à essayer avec un contrôleur branché ; les tests de l'orchestration utiliseront un faux transport.
- **Fait (étape 1)** : `ControllerModel.detect(portName:)`, `isControlPort(named:)` (Launchpad : port MIDI, pas DAW), `isConsistent(with:)` (fabricant Novation `00 20 29` / Akai `47`). Les octets « famille » de la réponse d'identité ne sont pas encore connus : à relever sur le matériel (journaliser la réponse), puis à ajouter ici et dans `docs/hardware/`.
- `LalabobMIDI` : session CoreMIDI dans un `actor` (sources, destinations, notifications de branchement).
- Détection automatique par requête d'identité → `ControllerModel` → pilote.
- Appui pad → `ShowController` → son ; LED synchronisées avec l'écran (RVB sur Launchpad, palette + canal sur APC).
- APC : faders 1–8 → niveaux de colonne.
- Reconnexion à chaud sans arrêter le son.
- **Terminé quand** : sur chaque contrôleur disponible, un appui joue le bon son, les LED ont les couleurs de l'écran, les faders de l'APC bougent ceux de l'écran, y compris après débranchement. Points ⚠︎ de `docs/hardware/` vérifiés.

### J3 — Lumière (LightKey) 🟡 code terminé, essai réel à faire (branche `j3/lumiere`, empilée sur `j2/controleurs`)
**Décision du 30/10/2026 (ADR 0004)** : les notes des pads sont déjà mappées dans LightKey, qui écoute directement le contrôleur. **Pas de traduction.**
- Appui physique sur un pad lumière : rien côté Lalabob (LightKey le reçoit). LED : couleur du pad, en permanence.
- Clic à l'écran (Live) : la même note que le contrôleur est envoyée sur le port virtuel « Lalabob Lumière » (Note On 127, Note Off après 100 ms) ; note du contrôleur connecté ou du dernier connu.
- Couleur des pads lumière : via l'inspecteur minimal du J4.
- **Fait** : source virtuelle dans `CoreMIDISession` (identifiant unique conservé), `MIDITransport.sendLighting`, `ShowController.lightPresses` + `lastControllerModel`, `ControllerSession.watchLightPresses`. 6 tests (`LightingTests`).
- **Essai réel (à cocher)** : ☐ LightKey voit « Lalabob Lumière » ☐ ajouter ce port à l'écoute dans LightKey avec le même mapping ☐ un clic à l'écran déclenche la cue ☐ un appui physique ne la déclenche qu'une fois.
- Abandonné : faders lumière en CC (à rediscuter si besoin), retour LED de LightKey, comportements impulsion / bascule / maintenu côté Lalabob.

### J4 — Édition et spectacles · palier « utilisable en répétition » 🟡 code terminé, essai réel à faire (branche `j4/edition-spectacles`, empilée sur `j3/lumiere`)
**Avancement** — étape 1/4 ✅ édition + ⌘Z dans `ShowController` · étape 2/4 ✅ format `.lalabob` + import des sons · étape 3/4 ✅ interface (onglets, inspecteur minimal, glisser-déposer, raccourcis, bibliothèque) · étape 4/4 ✅ document, sauvegarde auto, contrôleur partagé entre fenêtres. **Reste : essai réel** (check-list ci-dessous), surtout ouverture sur l'autre Mac.
- **Fait (étape 1)** : `ShowEditing.swift` — placer (type de colonne vérifié), nouvelle cue, vider, déplacer / échanger, ⌥-dupliquer (case vide), couper / copier / coller (nouvel identifiant), ⌘D (case libre en dessous), inspecteur (titre, sous-titre, teinte, intensité LED ; 80 caractères max), onglets (ajouter ≤ 64, renommer, réordonner, supprimer sauf le dernier). Tout passe par `commit` : une annulation par opération, aucune si rien ne change, onglet affiché toujours valide. Moteur : un pad déplacé pendant sa lecture continue (relancé à sa position, micro-coupure possible). 24 tests Engine + 1 test audio.
- **Fait (étape 2)** : `ShowPackage` (LalabobModel) — paquet `show.json` (JSON trié, lisible) + `Audio/` ; lecture = décodage + `validate()`, `show.json` limité à 10 Mo, noms dangereux de `Audio/` ignorés, sons manquants signalés sans bloquer l'ouverture, réécriture qui conserve les sons existants. `AudioClip.safeFileName` / `uniqueFileName`. `AudioImporter` (Engine) — copie (clone APFS) dans le dossier de travail, même fichier = pas de doublon, homonyme = « nom 2 », formats audio seulement ; pad pré-rempli (titre = nom, teinte stable). `ShowController.dropAudioFile`. 18 tests modèle + 7 tests Engine.
- **Fait (étape 3)** : `App/` découpé (`HeaderView`, `GridView`, `InspectorView`, `LibraryView`, `LalabobCommands`). Onglets : pastille numérotée, nom, nombre de pads, + / ⌘T, double-clic pour renommer, glisser pour réordonner, menu contextuel ; ⌘1…⌘9 (menu Grilles). Grille : glisser un pad = déplacer / échanger, ⌥ = dupliquer (badge « Copie »), dépôt d'un fichier du Finder ou de la bibliothèque = import + pad ; ⌘X / ⌘C / ⌘V / ⌫ quand la grille a le focus, ⌘D dans le menu Édition. Inspecteur minimal (mode Édition) : titre, sous-titre, 16 pastilles, intensité LED, actions ; case lumière vide → « Nouvelle cue ». Bibliothèque : recherche, dossiers favoris (signets sandbox), sons avec durée, point turquoise si déjà utilisé. `AudioLibrary` / `LibraryController` (Engine) : 14 tests. Pas encore de pré-écoute (à placer au J5 avec l'inspecteur complet).
- **Fait (étape 4)** : `DocumentGroup` + `LalabobDocument` (`ReferenceFileDocument`, type `fr.flodevbob.lalabob.show`, extension `.lalabob`, paquet déclaré dans `project.yml`). SwiftUI enregistre en arrière-plan : le document lit une copie verrouillée du spectacle (`ShowMirror`, tenue à jour par `ShowController.onShowChange`). Sons : copiés à l'ouverture dans un dossier de travail (caches de l'app), les imports y arrivent, l'enregistrement n'ajoute au paquet que les nouveaux. Sauvegarde automatique de macOS (déclenchée par l'annulation). Une fenêtre = un `ShowController` = un moteur audio ; une seule `ControllerSession` pour l'app, rattachée à la fenêtre active (`attach` / `detach`), sans arrêter les sons des autres fenêtres. Sons manquants signalés à l'ouverture. Boutons et dossier « Sons d'essai » retirés. 6 tests (`MultiDocumentTests`, `ShowMirrorTests`).
- **Essai réel J4 (à cocher)** : ☐ nouveau spectacle → glisser des sons du Finder et de la bibliothèque → ⌘S → fermer → rouvrir : tout est là ☐ copier le `.lalabob` sur l'autre Mac et l'ouvrir ☐ ⌘Z / ⇧⌘Z sur chaque opération ☐ ⌥-glisser = copie ☐ onglets : ajout, renommage, réordonnancement, ⌘1…⌘9 ☐ deux spectacles ouverts : le contrôleur suit la fenêtre active, aucun son ne s'arrête en changeant de fenêtre ☐ sauvegarde automatique (quitter sans ⌘S puis rouvrir).
- **Limites connues J4** : les niveaux de fader ne marquent pas le document comme modifié (enregistrés avec la modification suivante) ; à l'ouverture, les sons sont recopiés dans le dossier de travail (quelques secondes pour un très gros spectacle) ; les sons retirés de la grille restent dans le paquet ; pas de pré-écoute (J5).
- **Cadenas (décision du 30/10/2026)** : remplace Édition / Live. Verrouillé = on joue (clic = appui), bibliothèque et inspecteur masqués, toute édition refusée **dans `ShowController`** (y compris ⌘Z) avec un bandeau ; déverrouillé = clic sélectionne, double-clic écoute. Spectacle enregistré → s'ouvre verrouillé ; nouveau → déverrouillé. ⌘L. 13 tests (`LockTests`). Couvre l'essentiel du « mode Spectacle » prévu au J6.
- Inspecteur minimal (décision du 30/10/2026) : titre, sous-titre, 16 pastilles de couleur, intensité LED, pour tous les pads (sons et lumière). Forme d'onde, élagage, fondus : J5.
- Document `.lalabob` (`FileDocument`, paquet : `show.json` + dossier `Audio/` où les sons sont copiés), `Show.validate()` à l'ouverture.
- Onglets de grilles (ajout, renommage, réordonnancement), raccourcis ⌘1…⌘9.
- Bibliothèque de fichiers à gauche (signets de portée sandbox), recherche, glisser-déposer vers les pads.
- Réagencement : glisser = déplacer / échanger, ⌥-glisser = dupliquer, ⌘X/C/V/D, ⌫, ⌘Z via `UndoManager`.
- Édition titre / sous-titre / couleur ; sauvegarde automatique.
- **Terminé quand** : la troupe monte un spectacle complet et le rouvre sur l'autre Mac.

### J5 — Inspecteur et design final 🚧 (branche `j5/inspecteur-design`, empilée sur `j4/edition-spectacles`)
**Avancement** — étape 1/5 ✅ icônes Iconoir + police Fredoka (ADR 0005) · étape 2/5 ✅ réglages audio du pad (élagage, fondus, boucle, nouvel appui) + forme d'onde (Accelerate, cache) · étape 3/5 ✅ inspecteur complet (transport, forme d'onde, poignées, tête de lecture ; pad lumière : Tester) · étape 4/5 ✅ pré-écoute dans la bibliothèque · étape 5/5 ✅ fader vertical, égaliseur des pads, accessibilité (vumètre réel reporté). **Reste : validation côte à côte avec la maquette et essai réel.**
- **Fait (étape 2)** : `AudioClip.trimmed` / `withFades` (bornés au fichier, poignées qui ne se croisent pas, fin du fichier = pas de fin), `ShowController.setTrim` / `setFades` / `setLoops` / `setRetrigger` (⌘Z, refusés si verrouillé), `Waveform.analyze` (pics par blocs avec `vDSP_maxmgv`, fichier jamais chargé entier), `WaveformStore` (mémoire + disque, clé chemin + taille + date). Moteur : modifier les réglages d'un pad qui joue ne coupe plus son son (nouveaux réglages au prochain appui). 4 + 6 + 4 tests.
- **Fait (étape 3)** : `InspectorView` en trois panneaux — transport (Lecture / Relancer, Pause / Reprendre, Stop, temps écoulé / durée utile, badge « En pause », nom + format du fichier via `AudioFileInfo.describe`, fondus avec durée, boucle, nouvel appui), `WaveformEditor` (zones élaguées assombries, poignées déplaçables = une modification annulable au relâchement, courbes de fondu en pointillés, tête de lecture, accessible au clavier / VoiceOver), pad lumière (bouton Tester, rappel de la note envoyée à LightKey), apparence (titre, sous-titre, 16 teintes, intensité LED). 3 tests (`AudioFileDescriptionTests`). **Rendu à valider à l'œil dans l'app** (glisser des poignées, tête de lecture).
- **Fait (étape 4)** : zone de pré-écoute en bas de la bibliothèque (bouton lecture / stop, nom, mini forme d'onde avec avancement) ; double-clic sur un son = pré-écoute. `AudioPreviewing` / `AVAudioPreviewer` (`AVAudioPlayer`, joue sur la sortie choisie pour le spectacle, séparé du moteur : pas de fader ni de pad), `PreviewController` (un son à la fois, refusé et arrêté si verrouillé, erreur affichée, « Tout arrêter » l'arrête aussi). 7 tests avec faux lecteur ; **le vrai lecteur n'a pas de test automatique** (à écouter : la sortie choisie est-elle respectée ?).
- **Fait (étape 5)** : `VerticalFader` (rail, poignée blanche arrondie, valeur en dB via `Gain.formatDecibels`, double-clic = 80 %, réglable au clavier / VoiceOver, actif même verrouillé), `MiniEqualizer` animé sur les pads en lecture (figé en pause), 4 tests d'affichage des dB. **Reporté : le vumètre.** Il faut mesurer le vrai signal de chaque colonne dans le moteur audio (tap sur les mélangeurs, calcul de crête sans verrou ni allocation côté audio) ; un vumètre factice serait trompeur sur scène. À faire au J6 avec les tests de charge. **Non fait aussi** : badge « ON » des cues lumière (l'état de LightKey n'est pas connu de Lalabob, ADR 0004) ; contrastes à auditer (sous-agent d'accessibilité Xcode disponible).
- **Décision du 30/10/2026** : icônes **Iconoir** au lieu de Phosphor (ADR 0005).
- **Fait (étape 1)** : 25 icônes en SVG (23 Iconoir + projecteur et cadenas ouvert dessinés), `Icon`, `IconLabel`, `Button(…, icon:)`, Fredoka enregistrée au lancement (`Fonts.register()`), licences livrées ; tous les symboles système de l'app remplacés. 27 tests (`LalabobDesignTests`).
- Panneau du bas : nom du fichier, fondus, boucle, nouvel appui, forme d'onde (pics calculés avec Accelerate, cache disque), poignées d'élagage, tête de lecture, lecture / pause / stop.
- Palette 16 teintes, intensité LED, police Fredoka (logo), icônes Iconoir + projecteur sur mesure, animations, accessibilité (VoiceOver, contrastes).
- **Terminé quand** : l'app est fidèle à la maquette, validée côte à côte.

### J5b — Inspecteur compact (branche `j5b/barre-propertes-compacte`, empilée sur `j5/inspecteur-design`)
**Décision du 31/10/2026** : le panneau du bas construit au J5 (étape 3) grandissait librement et dupliquait
le titre/sous-titre (en-tête + champs toujours visibles). Nouvelle version, dans l'esprit de la maquette
mise à jour le même jour : hauteur plafonnée à `Metrics.inspectorHeight` (196 px, ≈ 1/5 d'une fenêtre de
régie), titre et sous-titre éditables en double-cliquant dans l'en-tête (plus de champs séparés), contrôles
réduits (`controlSize(.mini)`), ligne de métadonnées et rappel « Glissez les poignées » retirés.
- **Fait** : `InspectorView.swift` réécrit (en-tête `InspectorHeader` avec édition par double-clic,
  `TransportPanel` et `AppearancePanel` compactés, `LightPanel` resserré) ; `Metrics.inspectorHeight` ajouté
  (`LalabobDesign/Theme.swift`). Aucun test automatique touché (pas de cible de tests sur `App/`).
- **Non compilé** : écrit sans Mac, comme indiqué dans `CLAUDE.md`. Relecture attentive faite (accolades et
  parenthèses comptées, API de `ShowController` vérifiées dans leurs fichiers sources), mais à compiler et
  essayer dans Xcode avant de fusionner.
- **Essai à faire** : ☐ ça compile ☐ le panneau ne dépasse pas ~196 px même avec un titre long ☐ double-clic
  sur le titre puis sur le sous-titre : édition, Entrée valide, Échap annule, un clic ailleurs valide aussi
  ☐ fondu entrée/sortie : interrupteur et réglage fin de la durée toujours accessibles ☐ pad lumière : Tester,
  couleur, intensité LED ☐ au clavier / VoiceOver, les boutons et champs restent accessibles.
- **Limite connue** : à la taille minimale de la fenêtre (1100 × 720), 196 px représente plus que 1/5 de la
  hauteur (≈ 27 %) ; la proportion visée (1/5) correspond à une fenêtre de régie d'environ 950–1000 px de haut.

### J5c — Inspecteur « solution B » (branche `j5c/inspecteur-solution-b`, empilée sur `j5b/barre-propertes-compacte`)
**Décision du 31/10/2026** : parmi les pistes A / B / C / D de la maquette, on implémente la **B** (deux bandes).
- **Bande du haut (52 px)** : transport (lecture/relance, pause, stop, boucle, temps, badge « PAUSE ») · titre et
  sous-titre (double-clic) · nom du fichier d'origine · « Nouvel appui » (Relancer / Arrêter) · fondus (popover) ·
  **couleur = un seul bouton (teinte en cours) qui ouvre un popover** (16 teintes + intensité LED) · menu Actions.
  Filets verticaux entre les groupes sans rapport.
- **Bande du bas (120 px)** : **jauge de volume du pad** (−60…+12 dB, valeur en dB, double-clic = 0 dB) + forme d'onde
  pleine largeur. Total ≈ 195 px (≤ `Metrics.inspectorHeight`).
- **Fait** : `AudioClip.gainRange` / `withGain`, `ShowController.setGain` (⌘Z, refusé si verrouillé),
  `Gain.gaugePosition` / `decibels(forGaugePosition:)` / `formatDecibels(db:)`, `Surface.loopAccent`,
  `InspectorView.swift` réécrit. Tests écrits d'abord : `ClipSettingsTests` (+2), `ClipEditingTests` (+2),
  `TrackGainGaugeTests` (+5).
- **Écarts avec la maquette B (à valider)** : (1) **Fondus** : absents de la maquette, gardés dans un popover « Fondus » ;
  (2) **Couper / Copier / Coller / Dupliquer / Vider** regroupés dans un menu « Actions » (raccourcis inchangés) ;
  (3) pastille de position (C2·L5) retirée de l'en-tête, gardée en infobulle ; (4) pas de chevron système (Iconoir
  uniquement) : petit chevron dessiné ; (5) jauge de 46 px de large (au lieu de 34) pour tenir « −12,0 dB ».
- **Limites connues** : le volume du pad s'applique **au prochain déclenchement** (il est « cuit » dans les échantillons
  des sons courts) — pas de réglage en direct pendant la lecture ; à la largeur minimale de fenêtre, l'en-tête est
  dense (le nom de fichier est tronqué en premier) ; le clic simple sur la jauge ne déplace pas la poignée (glisser
  seulement, pour que le double-clic reste fiable).
- **Correction au passage** : la version J5b utilisait `Color(hex:)` (interne à `LalabobDesign`) depuis `App/` — erreur de
  compilation latente, supprimée par cette réécriture.
- **Non compilé** : écrit sans Mac. `swift` n'est pas disponible ici, les tests n'ont **pas** été exécutés.
- **Essai à faire** : ☐ ça compile ☐ `make test` vert (nouveaux tests inclus) ☐ la barre ne dépasse pas ~196 px
  ☐ double-clic titre / sous-titre : édition, Entrée valide, Échap annule ☐ pause : le bouton s'ambre + badge PAUSE,
  reprise ok ☐ boucle ☐ « Nouvel appui » Relancer / Arrêter se comporte comme annoncé sur un pad qui joue
  ☐ popover couleur : choisir une teinte met la LED du contrôleur à jour ; l'intensité LED aussi ☐ popover Fondus
  ☐ jauge : glisser = une seule annulation (⌘Z), double-clic = 0 dB, effet audible au prochain appui
  ☐ pad lumière : Tester, couleur ☐ case vide : Coller dans le menu Actions ☐ VoiceOver : jauge ajustable.

### J6 — Fiabilisation et livraison · palier « prêt pour le spectacle »
- Vumètre réel par colonne (mesure du signal dans le moteur, voir J5). Mode Spectacle : fait au J4 sous forme de cadenas (voir J4) ; reste à verrouiller aussi la pré-écoute. Tests de charge et d'endurance (3 h), scénarios de panne (contrôleur, carte son, LightKey), journal `OSLog`.
- Installation sur les deux Mac de régie, guide d'utilisation d'une page.
- **Terminé quand** : une répétition générale se déroule sans incident.

## Risques suivis

| Risque | Parade |
| --- | --- |
| Latence / craquements à forte charge | Test de charge dès J1, Instruments |
| Comportements MIDI non documentés (APC surtout) | Pilotes isolés, messages enregistrés, essais matériels tôt |
| Glisser-déposer SwiftUI limité (⌥ pour dupliquer) | Repli AppKit pour la grille si besoin |
| Format MIDI attendu par LightKey | Sans objet : LightKey apprend les notes du contrôleur (ADR 0004) |
