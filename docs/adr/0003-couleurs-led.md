# ADR 0003 — Couleurs des LED en RVB quand c'est possible

- Date : 30 octobre 2026
- État : acceptée

## Contexte

La maquette définit 16 teintes modernisées. Les contrôleurs ont une palette fixe de 128 couleurs
adressée par la vélocité, souvent éloignée de ces teintes.

## Décision

- Un pad stocke une `Tint`. Chaque pilote la traduit.
- Launchpad X / Mini MK3 / Pro MK3 : SysEx d'éclairage en **RVB** (type 3, 0–127 par canal),
  pour reproduire exactement la couleur vive de la maquette.
- APC mini mk2 : palette par vélocité (`TintSpec.paletteVelocity`) et luminosité par canal MIDI.
  Le SysEx RVB de l'APC pourra remplacer la palette après essai sur le matériel.

## Conséquences

- L'écran et le Launchpad affichent la même couleur.
- Les entrées de palette sont à vérifier sur chaque contrôleur et à corriger dans `Tint.swift`.
