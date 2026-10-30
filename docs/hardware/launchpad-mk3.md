# Launchpad X, Mini MK3, Pro MK3 — mode Programmeur

Source : [Launchpad X Programmer's reference manual](https://fael-downloads-prod.focusrite.com/customer/test/s3fs-public/downloads/Launchpad%20X%20-%20Programmers%20Reference%20Manual.pdf) (Novation).
Les manuels Mini MK3 et Pro MK3 suivent la même logique ; les points marqués ⚠︎ sont à vérifier sur le matériel.

## Ports

Le Launchpad expose deux ports USB-MIDI : « DAW » et « MIDI ». Lalabob utilise le port **MIDI**,
celui qui sert au mode Programmeur.

## Messages

| Rôle | Octets |
| --- | --- |
| En-tête SysEx | `F0 00 20 29 02 <modèle>` — X : `0C` ; Mini MK3 : `0D` ⚠︎ ; Pro MK3 : `0E` ⚠︎ |
| Mode Programmeur | `<en-tête> 0E 01 F7` (retour au mode Live : `0E 00`) |
| LED | `<en-tête> 03 <spec>… F7`, jusqu'à 81 specs par message |
| Spec statique | `00 <index> <palette>` |
| Spec clignotante | `01 <index> <couleur B> <couleur A>` |
| Spec pulsée | `02 <index> <palette>` |
| Spec RVB | `03 <index> <R> <G> <B>`, chaque canal 0–127 |
| Identité | requête `F0 7E 7F 06 01 F7` ; réponse avec fabricant `00 20 29` |

## Grille

En mode Programmeur, l'index d'une case vaut `(rangée depuis le bas + 1) × 10 + (colonne + 1)` :
11 en bas à gauche, 18 en bas à droite, 81 en haut à gauche, 88 en haut à droite.
Les appuis arrivent en Note On (vélocité 0 = relâchement). Les boutons de bord (rangée 9, colonne 9)
ne sont pas utilisés par Lalabob pour l'instant.

## À vérifier au jalon 2

- [ ] Octets modèle des Mini MK3 et Pro MK3.
- [ ] Le Pro MK3 utilise bien la même grille 11–88 en mode Programmeur.
- [ ] Rendu des couleurs RVB à côté de l'écran (ajuster si besoin dans `LaunchpadDriver.sevenBit`).
