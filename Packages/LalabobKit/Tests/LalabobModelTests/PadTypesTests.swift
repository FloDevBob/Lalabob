import Foundation
import Testing

@testable import LalabobModel

/// Types de colonnes et de pads, format `.lalabob` version 2 (fiche 05, ADR 0008). Aucun changement visible : ce sont les
/// fondations de la fiche 06 (conversions) et 07 (interface).
@Suite("Types de pads et format v2")
struct PadTypesTests {
    private static let sound = Pad(title: "Orage", tint: .azur, audio: AudioClip(fileName: "orage.wav"))
    private static let cue = Pad(
        title: "Plein feu", tint: .ambre, light: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 54)))
    private static let both = Pad(
        title: "Aube", tint: .rose, audio: AudioClip(fileName: "coq.wav"),
        light: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 54)))
    private static let waiting = Pad(
        title: "À venir", tint: .rose, light: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 54)),
        awaitsSound: true)

    // MARK: Type d'un pad

    @Test("Le type d'un pad se déduit de ses parties")
    func padKind() {
        #expect(Self.sound.kind == .audio)
        #expect(Self.cue.kind == .light)
        #expect(Self.both.kind == .mixed)
        #expect(Self.waiting.kind == .mixed)  // « son et lumière » choisi, son pas encore déposé
    }

    @Test("Constructeurs de commodité")
    func conveniences() {
        let sound = Pad.sound(title: "S", tint: .vert, clip: AudioClip(fileName: "a.wav"))
        #expect(sound.audio?.fileName == "a.wav")
        #expect(sound.light == nil)
        let cue = Pad.cue(title: "C", tint: .ambre, cue: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 1)))
        #expect(cue.light != nil)
        #expect(cue.audio == nil)
        #expect(cue.lightRetrigger == .turnOnOnly)
    }

    // MARK: Ce qu'une colonne accepte (3 × 3)

    @Test("Une colonne mixte accepte tout ; les autres, leur seul type", arguments: [
        (ColumnKind.audio, PadKind.audio, true), (.audio, .light, false), (.audio, .mixed, false),
        (.light, .audio, false), (.light, .light, true), (.light, .mixed, false),
        (.mixed, .audio, true), (.mixed, .light, true), (.mixed, .mixed, true),
    ])
    func accepts(column: ColumnKind, pad: PadKind, expected: Bool) {
        #expect(column.accepts(pad) == expected)
    }

    @Test("Ce que chaque type de colonne porte : volume et filtre pour le son et le mixte")
    func columnCapabilities() {
        #expect(ColumnKind.audio.hasAudio)
        #expect(ColumnKind.mixed.hasAudio)
        #expect(!ColumnKind.light.hasAudio)
    }

    // MARK: Validation

    private func show(with pad: Pad, in kind: ColumnKind) -> Show {
        var show = Show.new()
        show.grids[0].columns[0] = Column.empty(name: "C", kind: kind)
        show.grids[0].columns[0].slots[0] = pad
        return show
    }

    @Test("Un pad mixte est refusé dans une colonne son ou lumière, accepté dans une colonne mixte")
    func mixedPadNeedsMixedColumn() throws {
        #expect(throws: ShowValidationError.padKindMismatch(grid: 0, position: GridPosition(column: 0, row: 0))) {
            try show(with: Self.both, in: .audio).validate()
        }
        #expect(throws: ShowValidationError.padKindMismatch(grid: 0, position: GridPosition(column: 0, row: 0))) {
            try show(with: Self.both, in: .light).validate()
        }
        try show(with: Self.both, in: .mixed).validate()
    }

    @Test("Un pad son ou lumière est accepté dans une colonne mixte")
    func singlePadsInMixedColumn() throws {
        try show(with: Self.sound, in: .mixed).validate()
        try show(with: Self.cue, in: .mixed).validate()
    }

    @Test("Un pad sans aucune partie est refusé")
    func emptyPad() {
        let empty = Pad(title: "Vide", tint: .rouge)
        #expect(throws: ShowValidationError.valueOutOfRange("pad sans son ni lumière")) {
            try show(with: empty, in: .mixed).validate()
        }
    }

    @Test("« En attente de son » : accepté avec une cue seule, refusé avec un son déjà là")
    func awaitsSound() throws {
        try show(with: Self.waiting, in: .mixed).validate()
        var contradictory = Self.both
        contradictory.awaitsSound = true
        #expect(throws: ShowValidationError.valueOutOfRange("pad en attente de son")) {
            try show(with: contradictory, in: .mixed).validate()
        }
    }

    @Test("Les réglages de chaque partie restent validés (nom de fichier dangereux, message MIDI)")
    func partsStayValidated() {
        let unsafe = Pad(title: "x", tint: .rouge, audio: AudioClip(fileName: "../secret.wav"))
        #expect(throws: ShowValidationError.unsafeFileName("../secret.wav")) { try show(with: unsafe, in: .audio).validate() }
        let badMIDI = Pad(
            title: "x", tint: .rouge, audio: AudioClip(fileName: "a.wav"),
            light: LightCue(output: MIDIMessageSpec(kind: .note, channel: 16, number: 0)))
        #expect(throws: ShowValidationError.valueOutOfRange("message MIDI")) { try show(with: badMIDI, in: .mixed).validate() }
    }

    // MARK: Format version 2

    @Test("Écriture : version 2, les parties d'un pad à plat, rien d'inutile")
    func encodesVersion2() throws {
        var show = Show.new()
        show.grids[0].columns[0] = Column.empty(name: "C", kind: .mixed)
        show.grids[0].columns[0].slots = [Self.sound, Self.cue, Self.both, Self.waiting, nil, nil, nil, nil]
        #expect(show.formatVersion == 2)
        let text = try #require(String(data: try ShowPackage.encode(show), encoding: .utf8))
        #expect(text.contains("\"formatVersion\" : 2"))
        #expect(!text.contains("\"content\""))
        #expect(text.contains("\"audio\" : {"))
        #expect(text.contains("\"light\" : {"))
        #expect(text.contains("\"awaitsSound\" : true"))
        // Valeurs par défaut non écrites : un seul « awaitsSound », aucun « lightRetrigger » (4 pads, défaut partout).
        #expect(text.components(separatedBy: "awaitsSound").count == 2)
        #expect(!text.contains("lightRetrigger"))
    }

    @Test("Aller-retour v2 pour les trois types, avec « nouvel appui » de la lumière")
    func roundTripV2() throws {
        var toggling = Self.both
        toggling.lightRetrigger = .toggle
        var show = Show.new()
        show.grids[0].columns[0] = Column.empty(name: "Mixte", kind: .mixed)
        show.grids[0].columns[0].slots = [Self.sound, Self.cue, toggling, Self.waiting, nil, nil, nil, nil]
        show.grids[0].columns[1] = Column.empty(name: "Son", kind: .audio)
        let read = try ShowPackage.decode(try ShowPackage.encode(show))
        #expect(read == show)
        #expect(read.grids[0].columns[0].slots[2]?.lightRetrigger == .toggle)
        #expect(read.grids[0].columns[0].kind == .mixed)
    }

    // MARK: Lecture d'un vrai fichier version 1

    private func fixtureV1() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/show-v1", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    @Test("Un vrai show.json de version 1 se lit avec les mêmes valeurs, et se réécrit en version 2")
    func readsRealV1() throws {
        let data = try fixtureV1()
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"formatVersion\" : 1"))
        #expect(text.contains("\"content\""))  // bien l'ancienne forme

        let show = try ShowPackage.decode(data)
        let sound = try #require(show.grids[0][GridPosition(column: 0, row: 0)])
        #expect(sound.title == "Orage")
        #expect(sound.subtitle == "Ambiance")
        #expect(sound.tint == .azur)
        #expect(sound.ledIntensity == .half)
        #expect(sound.kind == .audio)
        let clip = try #require(sound.audio)
        #expect(clip.fileName == "orage.wav")
        #expect(clip.trimStart == 0.4)
        #expect(clip.trimEnd == 5.2)
        #expect(clip.fadeIn == 0.8)
        #expect(clip.fadeOut == 1.4)
        #expect(clip.loops)
        #expect(clip.retrigger == .stop)
        #expect(clip.gainDB == -6)
        #expect(sound.light == nil)

        let cuePad = try #require(show.grids[0][GridPosition(column: 6, row: 1)])
        #expect(cuePad.kind == .light)
        let cue = try #require(cuePad.light)
        #expect(cue.output.number == 54)
        #expect(cue.behavior == .toggle)
        #expect(cue.isPaired)
        #expect(cuePad.audio == nil)
        #expect(cuePad.lightRetrigger == .turnOnOnly)
        #expect(show.grids[0].columns[7].isFaderPaired)

        // Réécrit : version 2, et relu à l'identique.
        #expect(show.formatVersion == 2)
        let rewritten = try ShowPackage.encode(show)
        #expect(String(data: rewritten, encoding: .utf8)?.contains("\"content\"") == false)
        #expect(try ShowPackage.decode(rewritten) == show)
    }

    @Test("La colonne d'un pad lu en version 1 garde son type (son ou lumière)")
    func v1ColumnKinds() throws {
        let show = try ShowPackage.decode(try fixtureV1())
        #expect(show.grids[0].columns[0].kind == .audio)
        #expect(show.grids[0].columns[6].kind == .light)
    }

    @Test("Version 5 ou plus : refusée ; version 0 : refusée (la 4 est celle du DMX)")
    func unsupportedVersions() throws {
        var show = Show.new()
        show.formatVersion = 5
        #expect(throws: ShowValidationError.unsupportedFormatVersion(5)) { try show.validate() }
        show.formatVersion = 0
        #expect(throws: ShowValidationError.unsupportedFormatVersion(0)) { try show.validate() }
    }

    @Test("Un pad aux deux formes à la fois, ou sans aucune, est illisible (corrompu)")
    func malformedPads() throws {
        let data = try fixtureV1()
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var grids = try #require(object["grids"] as? [[String: Any]])
        var columns = try #require(grids[0]["columns"] as? [[String: Any]])
        var slots = try #require(columns[0]["slots"] as? [Any])
        var pad = try #require(slots[0] as? [String: Any])
        pad["audio"] = ["fileName": "x.wav", "loops": false, "retrigger": "restart", "gainDB": 0, "trimStart": 0]  // v1 + v2 mêlés
        slots[0] = pad
        columns[0]["slots"] = slots
        grids[0]["columns"] = columns
        object["grids"] = grids
        let mixedUp = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ShowPackageError.corrupt) { try ShowPackage.decode(mixedUp) }
    }
}
