# Fiche 08 — Documentation

Branche `j10/documentation`, en dernier (ou à la fin de chaque fiche si plus simple : dans ce cas cette fiche vérifie
seulement que tout est à jour).

## À mettre à jour
- `docs/DESIGN.md` : colonnes égales et liseré de type ; popover et menu « Type de colonne » ; feuille de confirmation ;
  pad mixte (capsule, états) ; case vide « + Son · + Cue » ; groupe Lumière de la barre du bas ; pastille de canal sur les
  onglets ; Réglages du spectacle (lumière commune) ; pastille Apple Music ; boutons de grille des contrôleurs.
- `docs/GUIDE.md` (une page pour la régie) et **l'aide intégrée** `App/HelpContent.swift` (à garder d'accord) :
  types de colonnes et de pads, « allumer seulement / basculer », un canal LightKey par grille et le réappairage des
  anciennes grilles, lumière commune, changer de grille depuis l'APC / le Launchpad, Apple Music (autorisation macOS,
  arrêter le script Python), **format v2 : mettre à jour les deux Mac ensemble**.
- `docs/FORMAT.md` : `lightChannel`, `sharedLight`, `parkedColumns`, `audio` / `light` / `awaitsSound` / `lightRetrigger`,
  version 2 (si les fiches précédentes ne l'ont pas déjà fait).
- `docs/hardware/apc-mini-mk2.md`, `launchpad-mk3.md` : valeurs relevées (boutons de scène, Shift, flèches, 9e fader) ;
  retirer les ⚠︎ confirmés.
- `docs/PLAN.md` : sections J9 et J10 (avancement, limites connues, check-lists d'essai réunies).
- `docs/plan-types-et-grilles.md` : marquer les étapes faites.
- ADR 0008 (format v2) et 0009 (Apple Music) présentes et à jour.

## Terminé quand
Un membre de la troupe peut préparer un spectacle avec des colonnes mixtes et des grilles en ne lisant que le guide.
