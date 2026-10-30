# ADR 0001 — Architecture modulaire

- Date : 30 octobre 2026
- État : acceptée

## Contexte

Lalabob doit être fiable en spectacle, maintenable par une petite équipe aidée de Claude Code,
et capable d'accueillir de nouveaux contrôleurs.

## Décision

- Une app SwiftUI fine (`App/`) et un package local `LalabobKit` en six modules :
  Model, Design, MIDI, ControllerDrivers, Audio, Engine.
- Un seul package à plusieurs modules plutôt que six packages : mêmes frontières de compilation,
  une seule configuration, tests lancés en une commande (`swift test`).
- `ShowController` est la seule source de vérité ; l'écran et les LED en sont des reflets.
- Les pilotes de contrôleurs sont des fonctions pures (octets ⇄ valeurs), testables sans matériel.
- Aucun framework tiers : SwiftUI, Observation, CoreMIDI, AVFoundation, Accelerate.

## Conséquences

- La logique se teste vite, sans Mac de régie ni contrôleur branché.
- Ajouter un contrôleur = ajouter un fichier dans `ControllerDrivers` et ses tests.
- L'app ne peut pas « tricher » en touchant directement le moteur audio ou le MIDI.
