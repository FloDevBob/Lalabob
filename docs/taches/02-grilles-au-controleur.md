# Fiche 02 — Changer de grille depuis le contrôleur

Branche `j9/grilles-au-controleur`. Skill `midi-driver`. Maquette : planche 6.

## Pour l'utilisateur
- **APC mini mk2** : les 8 boutons de scène à droite affichent les grilles 1 à 8 ; **Shift + bouton** les grilles 9 à 16.
  La LED du bouton de la grille affichée est allumée.
- **Launchpad Mini MK3** : les deux boutons en haut à gauche, **▲ = grille précédente, ▼ = grille suivante** ; chaque
  flèche est allumée s'il y a une grille de ce côté. Un appui = une grille (maintenir ne fait pas défiler).
- Marche **verrouillé comme déverrouillé**. N'arrête aucun son. Bouton d'une grille qui n'existe pas : rien.

## Aujourd'hui (code)
- `ControllerInput` (`ControllerDrivers/ControllerDriver.swift`) : `padPressed`, `padReleased`, `columnFader`, `columnStop`.
- APC (`APCMiniMK2Driver.interpret`) : notes 100–107 = stop de colonne ; les boutons de scène (112–119) sont ignorés.
- Launchpad (`LaunchpadDriver.interpret`) : ignore tout CC.
- LED des boutons stop : `stopButtonMessages(litColumns:)`, poussées par `ControllerSession.watchStopButtons` /
  `pushStopButtons`. **Attention** : une fonction appelée sur `any ControllerDriver` doit être une **exigence du protocole**
  (avec implémentation par défaut dans l'extension), pas seulement une extension — bug déjà rencontré.
- Changer de grille : `ShowController.selectGrid(at:)` (déjà permis verrouillé, ne coupe rien).

## Pilotes (purs, sans état)
- Nouveaux cas : `ControllerInput.gridSelect(index: Int)`, `.gridStep(delta: Int)`, `.shift(pressed: Bool)`.
- APC : note On 112–119 (vélocité > 0) → `.gridSelect(index: note - 112)` ; note 122 → `.shift(pressed: velocity > 0)`
  (et note Off → `.shift(pressed: false)`). ⚠︎ 112–119 et 122 à confirmer (constantes nommées).
- Launchpad (mode Programmeur) : CC 91 valeur > 0 → `.gridStep(delta: -1)`, CC 92 valeur > 0 → `.gridStep(delta: +1)`. ⚠︎ à confirmer.
- LED : nouvelle exigence `gridButtonMessages(current: Int?, count: Int, shiftHeld: Bool) -> [MIDIEvent]`
  (défaut : `[]`).
  - APC : pour i in 0..<8, grille = i + (shiftHeld ? 8 : 0) ; allumée (vélocité 1, canal 1) si c'est la grille courante,
    éteinte (0) sinon. ⚠︎ Si le relevé montre qu'une vélocité donne un clignotement ou un niveau faible, **ne pas** l'utiliser
    pour « la grille existe » sans accord (le clignotement distrait en scène).
  - Launchpad : CC 91 allumé si current > 0, CC 92 allumé si current < count − 1 (couleur de palette verte, la même valeur
    que celle utilisée pour les pads atténués ; à défaut une constante commentée).
- `shutdownMessages` : éteindre aussi ces boutons (ajouter `gridButtonMessages(current: nil, count: 0, shiftHeld: false)`).

## Moteur (`ControllerSession`)
- Tenir `shiftHeld` (dans la session, pas dans le pilote).
- `.gridSelect(i)` → `attachedController?.selectGrid(at: i + (shiftHeld ? 8 : 0))`.
- `.gridStep(d)` → `selectGrid(at: selectedGridIndex + d)` (borné, pas de boucle).
- Pousser les LED de ces boutons à la connexion, à chaque changement de grille, au changement du nombre de grilles et à
  l'appui / relâchement de Shift (même modèle que `watchStopButtons` : observer, ne renvoyer que si ça change).
- Les fenêtres multiples : seule la fenêtre attachée (`attach` / `detach`) change de grille.

## Tests (écrire d'abord)
- `ControllerDriversTests/DriverTests.swift` : messages enregistrés → bons `ControllerInput` (scène 1 et 8, Shift appui /
  relâchement, flèches ▲ ▼, relâchement ignoré) ; `gridButtonMessages` (courante 2 sur 3 grilles, avec Shift, aucune).
- `LalabobEngineTests/ControllerSessionTests.swift` (`FakeMIDITransport`) : scène 2 → grille 2 ; Shift + scène 1 → grille 9 ;
  grille inexistante → rien ; flèche au bout → rien ; verrouillé → marche ; un son qui joue continue (moteur factice) ;
  LED renvoyées après changement de grille et pas en double.

## Essai sur le matériel
☐ Relever au banc d'essai les notes des boutons de scène et de Shift, les CC des flèches du Launchpad ; les reporter dans
`docs/hardware/apc-mini-mk2.md` et `launchpad-mk3.md` ☐ LED vertes sur l'APC, ce que donnent les vélocités 1, 2, 3
☐ changement de grille pendant un son : il continue ☐ Shift + bouton ☐ Launchpad ▲ ▼ et leurs LED ☐ ⌘Q éteint ces boutons.

## Terminé quand
Tests verts ; les deux contrôleurs changent de grille ; constantes matérielles confirmées ou marquées ⚠︎.
