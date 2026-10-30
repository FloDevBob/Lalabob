import Foundation
import Testing
@testable import LalabobModel

@Suite("Spectacle")
struct ShowTests {
    @Test("Une grille vide fait 8 × 8, avec les deux colonnes de droite en lumière")
    func emptyGridShape() {
        let grid = PadGrid.empty(name: "Test")
        #expect(grid.columns.count == 8)
        #expect(grid.columns.allSatisfy { $0.slots.count == 8 && $0.slots.allSatisfy { $0 == nil } })
        #expect(grid.columns.map(\.kind) == [.audio, .audio, .audio, .audio, .audio, .audio, .light, .light])
    }

    @Test("Un spectacle survit à l'enregistrement puis à la relecture")
    func codableRoundTrip() throws {
        var show = Show.new(name: "Match du 14 novembre")
        show.grids[0][GridPosition(column: 1, row: 0)] = Pad(
            title: "Porte", subtitle: "Grincement lent", tint: .turquoise,
            content: .audio(clip: AudioClip(fileName: "porte.wav", trimStart: 0.1, fadeOut: 2, loops: true))
        )
        show.grids[0][GridPosition(column: 6, row: 0)] = Pad(
            title: "Plein feu", tint: .blanc,
            content: .light(cue: LightCue(output: MIDIMessageSpec(kind: .note, channel: 1, number: 36)))
        )

        let data = try JSONEncoder().encode(show)
        let decoded = try JSONDecoder().decode(Show.self, from: data)

        #expect(decoded == show)
        try decoded.validate()
    }

    @Test("La duplication crée un nouvel identifiant mais garde le contenu")
    func duplication() {
        let pad = Pad(title: "Gong", tint: .ambre, content: .audio(clip: AudioClip(fileName: "gong.aif")))
        let copy = pad.duplicated()
        #expect(copy.id != pad.id)
        #expect(copy.title == pad.title && copy.content == pad.content)
    }
}

@Suite("Validation à l'ouverture")
struct ValidationTests {
    @Test(
        "Les noms de fichiers dangereux sont refusés",
        arguments: ["../secret.wav", "/etc/passwd", "sous/dossier.wav", ".cache", "", "a\\b.wav", "x:y.wav"]
    )
    func unsafeFileNames(name: String) {
        #expect(!AudioClip.isSafeFileName(name))
    }

    @Test("Les noms de fichiers simples sont acceptés", arguments: ["porte.wav", "Gong court.aif", "générique_fin.mp3"])
    func safeFileNames(name: String) {
        #expect(AudioClip.isSafeFileName(name))
    }

    @Test("Un pad audio dans une colonne lumière est refusé")
    func kindMismatch() {
        var show = Show.new()
        show.grids[0][GridPosition(column: 7, row: 2)] = Pad(
            title: "Intrus", tint: .rouge, content: .audio(clip: AudioClip(fileName: "x.wav"))
        )
        #expect(throws: ShowValidationError.padKindMismatch(grid: 0, position: GridPosition(column: 7, row: 2))) {
            try show.validate()
        }
    }

    @Test("Une grille tronquée est refusée")
    func truncatedGrid() {
        var show = Show.new()
        show.grids[0].columns.removeLast()
        #expect(throws: ShowValidationError.wrongColumnCount(grid: 0, count: 7)) {
            try show.validate()
        }
    }

    @Test("Une version de format future est refusée")
    func futureVersion() {
        var show = Show.new()
        show.formatVersion = Show.currentFormatVersion + 1
        #expect(throws: ShowValidationError.unsupportedFormatVersion(Show.currentFormatVersion + 1)) {
            try show.validate()
        }
    }
}

@Suite("Teintes")
struct TintTests {
    @Test("Les 16 teintes ont toutes des valeurs, avec des entrées de palette distinctes")
    func palette() {
        #expect(Tint.allCases.count == 16)
        let velocities = Tint.allCases.map(\.spec.paletteVelocity)
        #expect(Set(velocities).count == velocities.count)
    }

    @Test("Le texte d'un pad est toujours plus clair que son fond")
    func labelIsLighter() {
        func luminance(_ c: RGB) -> Int { Int(c.red) * 299 + Int(c.green) * 587 + Int(c.blue) * 114 }
        for tint in Tint.allCases {
            #expect(luminance(tint.spec.label) > luminance(tint.spec.surface), "\(tint)")
        }
    }

    @Test("Les intensités LED assombrissent ou éclaircissent la couleur vive")
    func intensities() {
        let base = Tint.rouge.spec.vivid
        #expect(LEDIntensity.full.apply(to: base) == base)
        #expect(LEDIntensity.half.apply(to: base).red < base.red)
        #expect(LEDIntensity.pastel.apply(to: base).green > base.green)
    }
}
