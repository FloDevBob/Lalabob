# Fiche 06 — Règles : conversions de type et jeu d'un pad mixte

Branche `j10/types-regles`, après la fiche 05. Cœur fonctionnel du bloc 2, **sans interface** (fiche 07).

## Pour l'utilisateur (ce que la fiche 07 rendra visible)
On change le type d'une colonne ou d'un pad ; élargir ne retire rien, restreindre retire ce qui ne rentre plus après
confirmation ; un ⌘Z annule. Un pad son et lumière lance le son et la cue.

## 1. Plan de conversion (pur, `LalabobModel/ConversionPlan.swift`)
```swift
public struct ConversionPlan: Equatable, Sendable {
    public var deletedPads: [Pad]            // supprimés (type refusé par la nouvelle colonne)
    public var padsLosingLight: [Pad]        // mixtes → son (cue et appairage oubliés)
    public var padsLosingSound: [Pad]        // mixtes → lumière (son et réglages retirés)
    public var faderPairingForgotten: Bool   // la colonne quitte Lumière alors que son fader était appairé
    public var filterReset: Bool             // la colonne quitte le son alors que son filtre n'était pas neutre
    public var isLossless: Bool { … }        // rien de tout ça
    public static func column(_ column: Column, to kind: ColumnKind) -> ConversionPlan
    public static func pad(_ pad: Pad, to kind: PadKind) -> ConversionPlan
}
extension Column { public func converted(to kind: ColumnKind) -> Column }
extension Pad    { public func converted(to kind: PadKind) -> Pad? }   // nil si le pad disparaît
```
Règles exactes (une ligne = un test) :

| Colonne de → vers | Pads | Fader / filtre |
| --- | --- | --- |
| Son → Son et lumière | inchangés | volume conservé |
| Lumière → Son et lumière | inchangés | devient volume (niveau 0,8), `isFaderPaired = false` |
| Son et lumière → Son | lumière : supprimés ; mixtes : perdent `light` | inchangé |
| Son et lumière → Lumière | son : supprimés ; mixtes : perdent `audio` (et `awaitsSound = false`) | filtre → 0, niveau 1 |
| Son → Lumière | tous supprimés | filtre → 0, niveau 1 |
| Lumière → Son | tous supprimés | niveau 0,8, `isFaderPaired = false` |

| Pad de → vers (colonne mixte seulement) | Effet |
| --- | --- |
| Son → Son et lumière | ajoute `light` = cue non appairée (même construction que `ShowEditing.blankLightPad`) |
| Lumière → Son et lumière | `awaitsSound = true` (pad « + Son ») |
| Son et lumière → Son | retire `light` |
| Son et lumière → Lumière | retire `audio`, `awaitsSound = false` |
| Son ↔ Lumière | remplace une partie par l'autre ; titre, sous-titre, teinte, intensité gardés |

## 2. Commandes (`LalabobEngine/ShowEditing.swift`)
- `ShowController.conversionPlan(column: Int, to: ColumnKind) -> ConversionPlan` et `conversionPlan(padAt:to:)` (lecture
  seule, pour la feuille de confirmation).
- `setColumnKind(_ column: Int, to: ColumnKind)` et `setPadKind(at: GridPosition, to: PadKind)` via `commit("Type de
  colonne")` / `commit("Type du pad")` : **une annulation**, refusés verrouillé, sans effet si même type ;
  `setPadKind` refusé hors colonne mixte. Si la fiche 01b est fusionnée et l'option active : passer une colonne en Lumière
  ou la sortir de Lumière s'applique à toutes les grilles (voir 01b, règle 5).
- Un pad qui **perd son son pendant sa lecture** : il s'arrête avec le fondu de 40 ms (vérifier que `syncAudio` /
  `.configure(show)` le fait déjà ; sinon envoyer un stop). Aucun autre son ne s'arrête.
- `place` / `movePad` / coller / ⌥-dupliquer : remplacer le test de type par `column.kind.accepts(pad.kind)`.
- `dropAudioFile` sur un pad **lumière** d'une colonne mixte : le pad devient mixte (ajoute `audio`, garde la cue,
  `awaitsSound = false`). Sur un pad son : remplace le son (comportement actuel).
- `newLightCue(at:)` : permis dans une colonne Lumière ou mixte.

## 3. Jouer un pad mixte
- `ShowController.play(at:)` (double-clic, Espace, Retour, menu) et `pressFromController(at:)` :
  - son : comme un pad son (`commands.yield(.trigger(pad.id))`, règle « nouvel appui » du clip) ;
  - lumière : `lightRetrigger == .turnOnOnly` → envoyer la note **seulement si** `lightState(at:) != .on` (état venu du
    retour de LightKey, ADR 0006) ; `.toggle` → envoyer toujours.
- `ControllerSession.watchInput` : aujourd'hui une colonne `.light` est relayée (Note On / Note Off au relâchement) et le
  reste passe par `pressFromController`. Nouveau routage **par case** :
  colonne Lumière → relais (inchangé) ; colonne Son → son (inchangé) ; colonne mixte → selon le pad : son seul → son ;
  lumière seule → relais ; mixte → son + relais soumis à la règle ci-dessus ; case vide → `pairingPress` seulement.
  Le Note Off du relâchement n'est envoyé que si le Note On l'a été.
- Pause, stop, stop de colonne, « Tout arrêter » : ne touchent jamais la lumière.
- Faders : colonne mixte = volume (comme Son : `syncColumnLevels`, `moveHardwareFader`, filtre, vumètre, bouton stop
  allumé) ; le relais CC ne concerne que les colonnes Lumière. Remplacer les tests `kind == .audio` par `kind.hasAudio`.

## 4. LED (`LEDPlanner.states`)
Pad mixte : si le son joue → pulsation (comme un son) ; en pause → atténué ; sinon état de la cue (allumée = pulsation,
éteinte = 25 %, inconnue = teinte normale).

## 5. Appairage (`LightPairing.swift`)
Les cases des colonnes mixtes sont des cibles comme celles des colonnes Lumière. Appairer une case qui contient un pad
**son** d'une colonne mixte lui ajoute la cue (le pad devient mixte). Les faders des colonnes mixtes ne s'appairent pas.

## Tests (écrire d'abord)
- `LalabobModelTests/ConversionPlanTests.swift` : une fonction de test par ligne des deux tableaux (contenu du plan **et**
  résultat de `converted`).
- `LalabobEngineTests/TypeConversionTests.swift` : ⌘Z rend l'état d'origine en une fois ; refus verrouillé ; même type =
  aucune annulation ; pad son qui joue puis perd son son → arrêté (moteur factice `RecordingAudioEngine`), les autres non ;
  `setPadKind` refusé hors colonne mixte ; glisser un son sur une cue d'une colonne mixte → pad mixte.
- `MixedPadPlayTests.swift` : appui sur un pad mixte → trigger + Note On ; second appui, retour « allumée » reçu → trigger
  seulement ; `.toggle` → Note On à chaque fois ; état inconnu → Note On ; relâchement → Note Off seulement si Note On.
- `LEDPlannerTests` : cas des pads mixtes. `LightPairingTests` : appairage d'un pad son en colonne mixte.

## Essai sur le matériel
☐ Pad mixte à l'APC : son + cue ☐ réappui : le son repart, la cue reste allumée ☐ mode « basculer » ☐ stop / Échap :
la lumière reste ☐ fader d'une colonne mixte = volume ☐ conversion pendant un son d'une autre colonne : il continue.

## Terminé quand
Tests verts, règles des deux tableaux couvertes, jeu des pads mixtes conforme.
