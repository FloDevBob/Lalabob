# Lalabob — règles du projet

Lalabob est une app macOS native de régie son + lumière pour une troupe d'improvisation.
Une grille 8×8 sur un Launchpad (ou APC mini mk2) : 6 colonnes de sons, 2 colonnes de commandes
MIDI vers LightKey. Sécurité de scène avant tout : **le son ne doit jamais s'arrêter tout seul.**

## Commandes

- `make test` — tests des modules cœur (Swift Testing). À lancer avant toute PR.
- `make project` — régénère `Lalabob.xcodeproj` depuis `project.yml` (XcodeGen).
- `make build` — compile l'app.
- Le projet Xcode est généré : ne jamais le modifier ni le committer. Éditer `project.yml`.

## Architecture (voir docs/adr/0001-architecture.md)

- `App/` est fine : vues SwiftUI qui lisent `ShowController` et envoient des commandes.
- Tout le reste vit dans `Packages/LalabobKit`, un module par responsabilité :
  - `LalabobModel` : types valeur (`struct`, `Codable`, `Sendable`). Aucun import d'Apple framework hors Foundation.
  - `LalabobMIDI` : messages MIDI en valeurs ; l'accès CoreMIDI sera isolé dans un `actor`.
  - `ControllerDrivers` : un pilote = une `struct` pure qui conforme `ControllerDriver`. Pas d'état, pas d'E/S.
  - `LalabobAudio` : AVAudioEngine derrière `AudioEngineControlling`.
  - `LalabobEngine` : `ShowController` (`@MainActor @Observable`), seule source de vérité.
  - `LalabobDesign` : jetons visuels de la maquette ; c'est le seul module SwiftUI du package.
- Dépendances autorisées : Model ← tout le monde ; Drivers → MIDI ; Engine → Model, Audio, MIDI, Drivers ;
  App → Engine, Design. Jamais l'inverse.

## Règles de code

- Swift 6, concurrence stricte. Pas de `@unchecked Sendable` ni de `nonisolated(unsafe)` sans ADR.
- **Thread audio** : aucune allocation, aucun verrou, aucun `print`, aucune E/S dans un rendu audio.
- Une teinte (`Tint`) est stockée, jamais un code couleur ; chaque pilote la traduit.
- Toute donnée lue d'un fichier passe par `Show.validate()` avant usage. Les sons restent dans `Audio/`
  (noms de fichiers simples, voir `AudioClip.isSafeFileName`).
- Toute modification du spectacle passe par `ShowController` (pour ⌘Z et la synchro des LED).
- Pas de dépendance tierce sans accord explicite et sans ADR.
- Identifiants et API en anglais ; commentaires, docs et textes d'interface en français.
- Tests : Swift Testing (`@Test`, `#expect`). Un pilote ou un format de fichier n'est jamais modifié sans test.

## Façon de travailler

1. Une tâche = une branche `jN/sujet-court` + une PR, relue avant fusion.
2. Écrire ou ajuster les tests d'abord, puis le code, puis `make test`.
3. Ce qui touche au matériel est testé avec des messages enregistrés (pas besoin du contrôleur).
   Ajouter à la description de PR une check-list d'essai sur le vrai contrôleur.
4. Une décision structurante = une page dans `docs/adr/`.
5. Je ne peux pas compiler l'app sans Mac : quand c'est le cas, le dire dans la PR.

Skills du dépôt : `lalabob-feature` (déroulé d'une tâche), `midi-driver` (pilote de contrôleur),
`release-check` (avant une représentation).

## Références

- Maquette : https://claude.ai/artifact/B82jshC6LzSB3FBxi7cAia
- Plan d'implémentation : https://claude.ai/artifact/UZQWshXj9GUVkjtFMFBJcm
- Protocoles matériels : `docs/hardware/`
