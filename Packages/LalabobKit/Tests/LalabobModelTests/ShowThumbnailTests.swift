import Foundation
import Testing

@testable import LalabobModel

/// Aperçu d'un spectacle dans la fenêtre d'accueil : la première grille en 8 × 8, et un résumé « 42 sons · 3 grilles ».
@Suite("Aperçu d'un spectacle (fenêtre d'accueil)")
struct ShowThumbnailTests {
    private static let cue = LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 54))

    @Test("Grille vide : 64 cases vides")
    func emptyGrid() {
        let thumbnail = ShowThumbnail(show: .new())
        #expect(thumbnail.cells.count == 64)
        #expect(thumbnail.cells.allSatisfy { $0 == .empty })
        #expect(thumbnail.gridCount == 1)
        #expect(thumbnail.summary == "Aucun son · 1 grille")
    }

    @Test("Les cases suivent l'ordre des colonnes ; une cue seule est en ambre, un son à sa teinte")
    func cells() {
        var grid = PadGrid.empty(name: "G")
        grid.columns[0].slots[0] = .sound(title: "A", tint: .vert, clip: AudioClip(fileName: "a.wav"))
        grid.columns[0].slots[2] = .sound(title: "B", tint: .azur, clip: AudioClip(fileName: "b.wav"))
        grid.columns[1].slots[0] = .sound(title: "C", tint: .rouge, clip: AudioClip(fileName: "c.wav"))
        grid.columns[6].slots[0] = .cue(title: "Plein feu", tint: .rose, cue: Self.cue)
        let thumbnail = ShowThumbnail(show: Show(name: "S", grids: [grid]))
        #expect(thumbnail.cells[0] == .tint(.vert))  // colonne 1, ligne 1
        #expect(thumbnail.cells[1] == .empty)
        #expect(thumbnail.cells[2] == .tint(.azur))
        #expect(thumbnail.cells[8] == .tint(.rouge))  // colonne 2, ligne 1
        #expect(thumbnail.cells[48] == .light)  // colonne 7, ligne 1 : la couleur du pad ne compte pas
        #expect(thumbnail.summary == "3 sons · 1 grille")
    }

    @Test("Un pad son et lumière garde sa teinte")
    func mixedPad() {
        var grid = PadGrid.empty(name: "G")
        grid.columns[0].kind = .mixed
        grid.columns[0].slots[0] = Pad(title: "Aube", tint: .rose, audio: AudioClip(fileName: "coq.wav"), light: Self.cue)
        let thumbnail = ShowThumbnail(show: Show(name: "S", grids: [grid]))
        #expect(thumbnail.cells[0] == .tint(.rose))
        #expect(thumbnail.summary == "1 son · 1 grille")
    }

    @Test("Seule la première grille est dessinée ; les sons de toutes les grilles sont comptés")
    func severalGrids() {
        var first = PadGrid.empty(name: "G1")
        first.columns[0].slots[0] = .sound(title: "A", tint: .vert, clip: AudioClip(fileName: "a.wav"))
        var second = PadGrid.empty(name: "G2")
        second.columns[3].slots[3] = .sound(title: "B", tint: .azur, clip: AudioClip(fileName: "b.wav"))
        second.columns[4].slots[4] = .sound(title: "C", tint: .azur, clip: AudioClip(fileName: "c.wav"))
        let thumbnail = ShowThumbnail(show: Show(name: "S", grids: [first, second, .empty(name: "G3")]))
        #expect(thumbnail.cells.filter { $0 != .empty }.count == 1)
        #expect(thumbnail.gridCount == 3)
        #expect(thumbnail.summary == "3 sons · 3 grilles")
    }

    @Test("Morceaux d'Apple Music comptés à part")
    func musicTracks() {
        var grid = PadGrid.empty(name: "M")
        grid.kind = .appleMusic
        grid.columns[0].kind = .music
        grid.columns[0].slots[0] = .track(MusicTrackRef(persistentID: "0123456789ABCDEF", title: "Titre", artist: "Artiste"), tint: .rose)
        let thumbnail = ShowThumbnail(show: Show(name: "S", grids: [grid]))
        #expect(thumbnail.cells[0] == .tint(.rose))
        #expect(thumbnail.summary == "1 morceau · 1 grille")
    }

    @Test("Un vrai spectacle de format 1, migré, donne un aperçu")
    func versionOne() throws {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/show-v1", withExtension: "json"))
        let show = try ShowPackage.decode(Data(contentsOf: url))
        let thumbnail = ShowThumbnail(show: show)
        #expect(thumbnail.cells.count == 64)
        #expect(thumbnail.gridCount == show.grids.count)
        #expect(thumbnail.cells.contains { $0 != .empty })
    }
}
