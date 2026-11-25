# Fiche 01 — Canal LightKey par grille

Branche `j9/canal-par-grille`. Maquette : planche 6 (menu de l'onglet ; **la pastille « Can. N » de la maquette a été retirée le 25/11/2026** : le canal ne s'affiche pas en permanence, il se lit dans l'infobulle de l'onglet et se change par clic droit).

## Pour l'utilisateur
La même touche du contrôleur déclenche une cue différente dans LightKey selon la grille affichée. Chaque onglet montre
son canal (« Can. 2 ») ; le clic droit sur l'onglet permet de le changer. Les cues des grilles 2 et suivantes d'un ancien
spectacle sont à réappairer (une alerte le dit une fois à l'ouverture).

## Aujourd'hui (code)
- Tout part sur le **canal 1** (`channel: 0` dans `MIDIEvent`, 0 = canal 1) :
  `ControllerSession.relayPad`, `relayFader`, `sendLightPress`, `sendLightFader` (`LalabobEngine/ControllerSession.swift`).
- Le retour de LightKey est lu dans `ControllerSession.watchLightingFeedback` ; `ControllerDriver.lightFeedback(for:)`
  (extension dans `ControllerDrivers/ControllerDriver.swift`) **ignore le canal**.
- L'état des cues est **par case** : `ControllerSession.lightStates` et `ShowController.lightStates`
  (`[GridPosition: LightState]`), passé par `ShowController.setLightStates`.
- `LightCue.output` (`MIDIMessageSpec`, avec un canal) existe dans le modèle mais **n'est pas utilisé** pour l'envoi : ne pas
  s'en servir, ne pas le supprimer.
- Le banc d'essai (`LightingTestBench`) a son propre canal pour ses clics : ne pas le changer.

## Modèle (`LalabobModel/Show.swift`)
- `PadGrid.lightChannel: Int?` — 1…16, `nil` = « Sans canal » (la lumière de cette grille n'envoie rien).
  Décodage avec `decodeIfPresent` (absent des anciens fichiers) ; ajouter une `init(from:)` comme `Column` le fait.
- `Show.firstFreeLightChannel(excluding:) -> Int?` (pur).
- `Show.assignMissingLightChannels() -> [Int]` (mutating, pur) : pour chaque grille sans canal, dans l'ordre, grille N →
  canal N si libre, sinon le premier libre, sinon `nil`. **Renvoie les index des grilles ≥ 2 dont des cues ou faders
  étaient appairés** et les marque non appairés (`LightCue.isPaired = false`, `Column.isFaderPaired = false`) : jusqu'ici
  tout partait sur le canal 1, leurs cues dans LightKey étaient celles de la grille 1.
- `Show.validate()` (`ShowValidation.swift`) : canal dans 1…16, deux grilles n'ont pas le même canal.
- Appel de la migration : à la lecture (`ShowPackage.read`), avant `validate()`. Ajouter à `ShowPackage.Contents` un champ
  `lightPairingsReset: [Int]` (même principe que `missingAudio`, qui sert déjà à signaler à l'ouverture).

## Moteur
- `ShowEditing.addGrid()` : la nouvelle grille prend `firstFreeLightChannel`. `moveGrid` ne change aucun canal.
  `removeGrid` libère le canal. Dupliquer une grille (si la fonction existe) : canal libre suivant, cues non appairées.
- `ShowController.setLightChannel(grid: Int, channel: Int?)` via `commit("Canal LightKey")`, refusé verrouillé ; refuse un
  canal déjà pris par une autre grille.
- `ShowController.currentLightChannel: Int?` = canal de la grille affichée.
- `ControllerSession` : remplacer chaque `channel: 0` des envois lumière par `UInt8(channel - 1)` du canal de la grille
  affichée ; **canal `nil` → ne rien envoyer** (et le noter dans le journal `Logger`).
- Retour : faire renvoyer le canal par le pilote (nouvelle fonction `lightFeedback(for:) -> (channel: Int, position:, state:)?`,
  canal 1…16) ; l'état devient **par canal** : `[Int: [GridPosition: LightState]]` dans la session.
  `ShowController.lightStates` reste `[GridPosition: LightState]` mais ne contient que **le canal de la grille affichée** ;
  au changement de grille (`selectGrid`), la session redonne l'état du nouveau canal (les LED suivent via `ledStates`).
- Mode d'appairage : `lightFeedbackArrived(at:)` / `faderFeedbackArrived(column:)` seulement si le canal du retour est
  celui de la grille affichée.

## Interface (`App/HeaderView.swift`, `GridTabsView`)
- ~~Pastille « Can. N » dans chaque onglet~~ retirée (décision du 25/11/2026) : le canal est dans l'infobulle de l'onglet.
- Menu contextuel de l'onglet : sous-menu « Canal LightKey » (1…16, canaux pris grisés avec le nom de leur grille,
  « Sans canal ») ; avant de changer : alerte « Les appairages de cette grille sont à refaire dans LightKey. » ;
  déverrouillé seulement.
- À l'ouverture d'un spectacle dont `lightPairingsReset` n'est pas vide : une alerte unique (même mécanisme que les sons
  manquants) : « Chaque grille a maintenant son propre canal LightKey. Les cues des grilles 2, 3… sont à réappairer. »

## Tests (écrire d'abord)
- Modèle : décodage sans `lightChannel` ; `assignMissingLightChannels` (3 grilles → 1, 2, 3 ; appairages des grilles 2+
  remis à faux ; grille 1 intacte ; 17 grilles → la 17e sans canal) ; validation (doublon, hors bornes).
- Engine (`FakeMIDITransport`, comme `LightingTests` / `LightFeedbackTests`) : appui physique sur une colonne lumière en
  grille 2 → Note On sur le canal 2 ; fader lumière → CC sur le canal 2 ; grille « Sans canal » → rien n'est envoyé ;
  retour sur le canal 2 n'allume que la grille 2 ; changement de grille → `lightStates` suit ; `addGrid` / `moveGrid` /
  `setLightChannel` (⌘Z, refus verrouillé, doublon refusé).
- Pilotes : `lightFeedback` renvoie le canal (Launchpad et APC).

## Essai sur le matériel (check-list de la PR)
☐ Banc d'essai réglé sur le canal 2 : LightKey apprend-il une cue **distincte** de la même note sur le canal 1 ?
☐ Deux grilles : même pad, deux cues différentes ☐ retour : la cue allumée s'affiche sur la bonne grille seulement
☐ ancien spectacle : alerte unique, grille 1 toujours appairée ☐ aucun son ne s'arrête en changeant de grille.

## Terminé quand
Tests verts ; chaque grille envoie et reçoit sur son canal ; un ancien spectacle s'ouvre avec l'alerte ; `docs/FORMAT.md`
mentionne `lightChannel`.
