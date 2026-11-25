# ADR 0008 — Pads « son et lumière » : un pad a un son et / ou une cue (format v2)

- Date : 25 novembre 2026
- État : acceptée (fiche 05 ; interface et règles de conversion : fiches 06 et 07, `docs/taches/`)

## Contexte

Jusqu'ici un pad était **soit un son, soit une cue** (`Pad.content`, une énumération `audio(clip:)` / `light(cue:)`) et une colonne était
**soit son, soit lumière**. La troupe veut des colonnes « son et lumière » et des pads qui lancent **un son et une cue en même temps**
(plan : `docs/plan-types-et-grilles.md`). Une énumération à deux cas ne peut pas représenter « les deux ».

## Décision

- `Pad.content` et `PadContent` disparaissent. Un pad a **deux parties facultatives** : `audio: AudioClip?` et `light: LightCue?`, plus
  `awaitsSound` (« son et lumière » choisi, son pas encore déposé) et `lightRetrigger` (`turnOnOnly` par défaut, ou `toggle`).
  Au moins une partie : un pad vide est refusé par `Show.validate()`.
- Le **type d'un pad** (`PadKind` : `audio`, `light`, `mixed`) est **déduit** des parties, jamais stocké : il ne peut pas contredire le contenu.
- `ColumnKind` gagne `mixed` ; `ColumnKind.accepts(_:)` dit ce qu'une colonne accepte (`mixed` : tout ; les autres : leur seul type) et
  `ColumnKind.hasAudio` ce qui porte un volume, un filtre, un vumètre et un stop (`audio`, `mixed`).
- **Format `.lalabob` version 2** : `audio` et `light` à plat dans le pad ; `awaitsSound` et `lightRetrigger` écrits seulement s'ils ne sont pas
  à leur valeur par défaut. Les fichiers de **version 1** (`content`) se lisent (conversion dans `Pad.init(from:)`) et se réécrivent en version 2.
  Un pad qui mêle les deux formes, ou dont `content` est vide, est refusé comme corrompu.
- Cette étape **ne change rien de visible** : aucun pad mixte ni colonne `mixed` ne peut encore être créé ; là où le code distinguait « son » et
  « lumière », il garde son comportement, et un pad qui aurait les deux se comporte comme un son jusqu'à la fiche 06.

## Conséquences

- **Une ancienne version de Lalabob ne peut pas ouvrir un fichier de version 2** : elle le refuse (`unsupportedFormatVersion`). Mettre à jour
  tous les Mac de régie en même temps ; garder une copie des spectacles avant de les rouvrir avec la nouvelle version.
- La migration est testée sur un **vrai** `show.json` de version 1 (`Tests/LalabobModelTests/Fixtures/show-v1.json`), pas sur un fichier écrit à la main.
- Les clés ajoutées avant cette décision (`lightChannel`, `sharedLight`, `parkedColumns`) restaient facultatives en version 1 ; elles font
  désormais partie de la version 2, sans changement.
- Les fiches 06 (conversions, jeu d'un pad mixte, LED) et 07 (interface) construisent sur ce modèle.
