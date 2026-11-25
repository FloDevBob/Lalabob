# Plan — types de colonnes et de pads, canal par grille, grilles au contrôleur, Apple Music

Version du 25/11/2026. Design validé : https://claude.ai/artifact/8KceUvus4vE8SWtJVY7iqM

## Ce qui est décidé

- **Colonnes** : 3 types (Son · Lumière · Son et lumière), 8 colonnes de **même largeur**, réglage **déverrouillé seulement**
  (pastille de l'en-tête → popover ; clic droit en raccourci).
- **Pads** : Son · Lumière · Son et lumière. Une colonne mixte accepte les trois ; les autres, leur seul type.
  Pad mixte = **capsule verticale** lecture + ampoule (22 px, même taille que le bouton lecture).
- **Faders** : cartes actuelles inchangées. Son et mixte = volume ; Lumière = CC vers LightKey.
- **Pad mixte** : nouvel appui = « allumer seulement » (option « basculer »). Pause / stop / Échap ne touchent jamais la lumière.
- **Canal LightKey par grille**, gardé quand on réordonne les onglets.
- **Changer de grille** : APC, bouton de scène N = grille N (Shift → 9–16) ; Launchpad, ▲ ▼ en haut à gauche.
- **9e fader → volume d'Apple Music**, intégré à l'app.
- Par défaut, sauf avis contraire : barre du bas d'un pad mixte en **variante A** (groupe Lumière), nouvelles grilles en 6 son + 2 lumière.

## Option « Colonnes lumière communes à toutes les grilles » (décidée le 25/11/2026)

- **Réglage du spectacle** (enregistré dans le `.lalabob`), dans un nouvel écran « Réglages du spectacle » (déverrouillé).
- **Activée** : les colonnes de type **Lumière** sont les mêmes dans toutes les grilles (positions, cues, faders,
  appairages) et partent sur un **canal commun** (1 par défaut, réglable). Changer de grille ne change pas la lumière ;
  on appaire une seule fois. Les colonnes **Son et lumière** restent propres à chaque grille (canal de la grille).
- **Désactivée** : chaque grille a ses propres colonnes lumière, sur son propre canal.
- **Activer** : les colonnes lumière de la **grille affichée** deviennent communes ; celles des autres grilles sont mises
  de côté (rien n'est perdu) et reviennent si on désactive.
- Option activée, rendre une colonne Lumière (ou cesser de l'être) s'applique à **toutes les grilles**, avec une
  confirmation qui détaille les pertes grille par grille.
- Les canaux des grilles évitent le canal commun.

## Règles de conversion (résumé)

- **Élargir** (vers Son et lumière) : rien n'est perdu, pas de confirmation.
- **Restreindre** : ce qui ne rentre plus est retiré (pads supprimés, ou partie son / lumière retirée), après une feuille qui
  le chiffre ; Son ↔ Lumière propose d'abord « Son et lumière ». Une conversion = un ⌘Z.
- Glisser un son sur un pad lumière d'une colonne mixte → pad mixte. Coller dans une colonne qui refuse le type → refusé.
- « Oublier » un appairage ne change rien dans LightKey.

## Apple Music : comment

Le script Python écoute le **CC 7, canal 3**, convertit 0–127 en 0–100 %, ignore les écarts < 2 %, et lance `osascript`
à chaque envoi (un processus par mouvement, et **il ouvre Music s'il est fermé**).

Dans l'app : **ScriptingBridge** (framework Apple, `SBApplication(bundleIdentifier: "com.apple.Music")`, propriété
`soundVolume`).
- Pas de processus lancé à chaque mouvement.
- `isRunning` permet de ne jamais ouvrir Music.
- Envoi hors du fil principal, la dernière valeur gagne (≤ 15 envois/s), seuil de 2 % repris du script.
- Bac à sable : entitlement Apple Events pour `com.apple.Music` + `NSAppleEventsUsageDescription` ; macOS demande l'accord une fois.
- ⚠︎ **À vérifier** : le script lit CC 7 / canal 3, la doc APC indique CC 56 / canal 1 pour le 9e fader. On relève le vrai
  message au banc d'essai, puis on le fige dans le pilote.
- Arrêter le script Python une fois l'app prête, sinon les deux pilotent Music en même temps.

## Étapes (une branche + une PR chacune, tests d'abord)

0. **Fusionner la pile J6 / J7 dans `main`** avant de commencer.

**J9 — Grilles et contrôleurs** (étapes indépendantes)

1. `j9/canal-par-grille` : canal stocké dans la grille ; cues, faders, relais et retour par canal ; pastille sur l'onglet.
   Migration : grille N → canal N, cues des grilles 2+ à réappairer (alerte unique).
1b. `j9/lumiere-commune` : option « Colonnes lumière communes » (réglages du spectacle, canal commun, mise de côté /
   restauration des colonnes des autres grilles). Après l'étape 1.
2. `j9/grilles-au-controleur` : boutons de scène APC (+ Shift, LED) et ▲ ▼ du Launchpad ; n'arrête aucun son, marche verrouillé.
3. `j9/fader-apple-music` : pilote APC (9e fader) → `MediaVolumeControlling` (Engine) → ScriptingBridge ; pastille
   et réglage dans l'en-tête ; ADR 0009.

**J10 — Types de colonnes et de pads**

4. `j10/colonnes-egales` : 8 colonnes de même largeur, liseré de type sous l'en-tête.
5. `j10/types-modele` : `ColumnKind.mixed`, pad à deux parties facultatives, format `.lalabob` v2 + migration, ADR 0008.
   ⚠︎ Un fichier v2 ne s'ouvre pas dans l'ancienne version : mettre à jour les deux Mac ensemble.
6. `j10/types-regles` : calcul des conversions (une fonction pure, testée cas par cas), `setColumnKind` / `setPadKind`,
   jeu d'un pad mixte, LED.
7. `j10/types-interface` : popover, clic droit, feuille de confirmation, case vide « + Son · + Cue », capsule, barre du bas.
8. `j10/documentation` : DESIGN, GUIDE, aide intégrée, PLAN, check-list d'essai réel.

## À relever sur le matériel

- Message réel du 9e fader de l'APC (CC 7 canal 3 ou CC 56 canal 1).
- Notes des boutons de scène (112–119) et de Shift (122), et ce que leurs LED savent afficher (allumé / clignotant / niveau ?).
- CC 91 / 92 des flèches du Launchpad en mode Programmeur.
- LightKey apprend-il bien le canal (même note, canal 1 ≠ canal 2) ? À tester au banc d'essai, réglé sur le canal 2.
