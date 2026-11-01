# ADR 0006 — Lumière : Lalabob relaie les appuis à LightKey et lit son retour

- Date : 1er novembre 2026
- État : acceptée (remplace l'ADR 0004)

## Contexte

L'ADR 0004 laissait LightKey écouter directement le contrôleur : Lalabob n'envoyait que les clics à l'écran, et les LED des cues
n'étaient que la teinte choisie. Le relevé du 1er novembre 2026 (`docs/hardware/lightkey-feedback.md`) a montré que LightKey
**renvoie l'état de chaque cue** (Note On vélocité 127 = allumée, Note Off vélocité 0 = éteinte, canal 1, notes de la disposition
du contrôleur, rafale d'état à l'ouverture) à la destination MIDI **du même nom que son entrée**. Il ne renvoie pas la couleur.

## Décision

- Lalabob crée un seul appareil virtuel **« Lalabob Lumière »** : une source (Lalabob → LightKey) et une destination du même
  nom (LightKey → Lalabob). L'ancien port « Lalabob Retour Lumière » est supprimé (LightKey ne lui répondait pas).
- **LightKey n'écoute que « Lalabob Lumière »** ; ses contrôleurs physiques sont désactivés dans ses réglages MIDI.
- **Appui physique** sur une colonne lumière : Lalabob le **relaie** (Note On à l'appui, Note Off au relâchement réel, vélocité 127 / 0,
  canal 1) et ne déclenche aucun son. **Faders** des colonnes lumière : le CC du contrôleur est relayé tel quel.
- **Clic à l'écran** : inchangé (même chemin, même file d'envoi, Note Off 100 ms plus tard).
- **État** : le retour met à jour `ShowController.lightStates` (le dernier message gagne). Allumée = contour, halo et ampoule sur le pad,
  LED qui pulse ; éteinte = ampoule et LED atténuées ; inconnue = comme avant. Lalabob ne déduit **jamais** « allumé » d'un envoi.
- **Canal dédié** (16) abandonné : le retour revient sur le canal appris (1).

## Conséquences

- Si LightKey écoute aussi le contrôleur, chaque appui bascule la cue **deux fois** (aucun effet visible) : à régler dans LightKey.
- Les appairages faits sur le contrôleur physique sont à refaire une fois, avec « Lalabob Lumière » (mode d'appairage : étape 4 du plan J7).
- La couleur réelle des cues n'est pas connue de Lalabob (pas dans le retour) : la teinte choisie dans l'app reste celle de l'écran et des LED.
- Fermeture de LightKey : rien ne le signale en MIDI, les pads gardent leur dernier état.
