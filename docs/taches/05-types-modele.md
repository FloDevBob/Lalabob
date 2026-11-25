# Fiche 05 — Modèle : types de colonnes et de pads, format v2

Branche `j10/types-modele`. **Aucun changement visible** : l'app doit se comporter exactement comme avant (aucun pad mixte
ne peut encore être créé). Écrire **ADR 0008** et mettre à jour `docs/FORMAT.md` dans la même PR.

## Aujourd'hui (code, `LalabobModel/Show.swift`)
- `ColumnKind { audio, light }` ; `Column.kind`.
- `Pad.content: PadContent` avec `enum PadContent { case audio(clip: AudioClip), light(cue: LightCue) }` ;
  `Pad.kind: ColumnKind` calculé.
- `Show.currentFormatVersion = 1` ; `Show.validate()` refuse un pad dont `pad.kind != column.kind`
  (`ShowValidationError.padKindMismatch`).
- ~70 usages de `.content`, `case .audio`, `case .light`, `kind == .audio/.light` dans : `ShowController`, `ShowEditing`,
  `LightPairing`, `LEDPlanner`, `ControllerSession`, `AudioImporter`, `WaveformStore`, `AVAudioEngineController`,
  `ShowPackage`, `ShowValidation`, et dans `App/` : `GridView`, `InspectorView`, `IdleBar`, `ContentView`.

## Nouveau modèle
```swift
public enum ColumnKind: String, Codable, Sendable { case audio, light, mixed }
public enum PadKind: String, Codable, Sendable { case audio, light, mixed }
public enum LightRetrigger: String, Codable, Sendable { case turnOnOnly, toggle }   // nouvel appui d'un pad mixte

public struct Pad {
    // … id, title, subtitle, tint, ledIntensity inchangés
    public var audio: AudioClip?
    public var light: LightCue?
    public var awaitsSound: Bool            // pad « son et lumière » choisi, son pas encore déposé
    public var lightRetrigger: LightRetrigger   // défaut .turnOnOnly
    public var kind: PadKind {               // calculé
        if audio != nil && light != nil { return .mixed }
        if light != nil { return awaitsSound ? .mixed : .light }   // awaitsSound n'a de sens qu'avec une cue
        return .audio
    }
}
extension ColumnKind { public func accepts(_ kind: PadKind) -> Bool }   // mixed accepte tout ; sinon type égal
```
- **Supprimer `PadContent`** et `Pad.content` : le compilateur listera chaque usage. Remplacer
  `if case .audio(let clip) = pad.content` par `if let clip = pad.audio`, etc. Là où le code distinguait « son » et
  « lumière », garder **le même comportement** pour les pads son et lumière ; pour `.mixed`, faire le choix le plus prudent
  et laisser un `// J10 fiche 06` (la fiche 06 le traitera) : par ex. `play` d'un pad mixte joue le son seulement.
- Colonne : là où le code teste `kind == .audio` pour « a un volume / un filtre / un stop / un vumètre », utiliser une
  propriété `ColumnKind.hasAudio` (audio, mixed) ; là où il teste `.light` pour « relais / CC lumière », `ColumnKind.isLightOnly`.
- Initialiseurs de commodité pour garder les appels lisibles : `Pad.sound(…)`, `Pad.cue(…)`.

## Format de fichier
- `Show.currentFormatVersion = 2`. Écriture : clés `audio`, `light`, `awaitsSound`, `lightRetrigger` (omises si nil /
  valeur par défaut, comme le reste du JSON trié).
- Lecture : `Pad.init(from:)` accepte **les deux** formes : si la clé `content` est présente (v1), la convertir ; sinon v2.
- `validate()` : version 1…2 ; pad avec au moins une partie (ou `light` + `awaitsSound`) ; `column.kind.accepts(pad.kind)` ;
  validation existante du son et de la cue inchangée.
- ⚠︎ Un fichier v2 ne s'ouvre pas dans une ancienne version de Lalabob (`unsupportedFormatVersion`) : le dire dans l'ADR,
  la PR et le guide (mettre à jour les deux Mac ensemble).

## Tests (écrire d'abord, `LalabobModelTests`)
- Décodage d'un **vrai JSON v1** (copier un `show.json` existant en chaîne de test : un pad son avec élagage / fondus, une
  cue appairée) → mêmes valeurs qu'avant.
- Aller-retour v2 pour les trois types ; `formatVersion` écrit = 2.
- Matrice `accepts` (3 × 3) ; validation : pad mixte dans colonne Son refusé, pad vide refusé, `awaitsSound` accepté.
- Tous les tests existants restent verts **sans modification de comportement** (adapter seulement la construction des pads).

## Terminé quand
Tests verts, app identique à l'usage, ADR 0008 et `docs/FORMAT.md` à jour, un vieux `.lalabob` s'ouvre et se réenregistre en v2.
