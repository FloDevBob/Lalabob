import Foundation
import Testing

@testable import LalabobModel

/// Option « Colonnes lumière communes à toutes les grilles » (fiche 01b) : activation, désactivation sans perte, canaux.
@Suite("Colonnes lumière communes")
struct SharedLightTests {
    static let cue = GridPosition(column: 6, row: 0)
    static let sound = GridPosition(column: 0, row: 0)

    private func cuePad(_ title: String, paired: Bool = false) -> Pad {
        Pad(title: title, tint: .blanc, content: .light(cue: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0), isPaired: paired)))
    }

    private func soundPad(_ file: String) -> Pad {
        Pad(title: file, tint: .vert, content: .audio(clip: AudioClip(fileName: file)))
    }

    /// Trois grilles (canaux 1, 2, 3). Grille 1 : cue en colonne 6. Grille 2 : sa propre cue en colonne 6 et une colonne
    /// lumière en position 3 (avec une cue). Grille 3 : la colonne 6 changée en colonne son, avec un son.
    private func sample() -> Show {
        var first = PadGrid.empty(name: "A")
        first[Self.cue] = cuePad("Face", paired: true)
        var second = PadGrid.empty(name: "B")
        second[Self.cue] = cuePad("Contre")
        second.columns[3] = Column.empty(name: "Lum B", kind: .light)
        second[GridPosition(column: 3, row: 2)] = cuePad("Rouge")
        var third = PadGrid.empty(name: "C")
        third.columns[6] = Column.empty(name: "Sons C", kind: .audio)
        third[Self.cue] = soundPad("pluie.wav")
        return Show(name: "S", grids: [first, second, third])
    }

    @Test("Aperçu : ce qui serait mis de côté, grille par grille")
    func preview() {
        let preview = sample().sharedLightParkingPreview(fromGrid: 0)
        #expect(preview == [
            SharedLightParking(grid: 1, columns: [3, 6, 7], padCount: 2),
            SharedLightParking(grid: 2, columns: [6, 7], padCount: 1),
        ])
    }

    @Test("Activer : les colonnes lumière de la grille affichée deviennent communes, le reste est mis de côté")
    func enable() throws {
        var show = sample()
        let enabled = show.enableSharedLight(fromGrid: 0)
        #expect(enabled)
        let shared = try #require(show.sharedLight)
        #expect(shared.columnIndices == [6, 7])
        #expect(shared.channel == 1)  // le canal de la grille d'origine : ses appairages restent valables
        #expect(show.grids[0].lightChannel == 4)  // la grille d'origine prend le premier canal libre
        for grid in show.grids {
            #expect(grid[Self.cue]?.title == "Face")
            #expect(grid.columns[6] == show.grids[0].columns[6])
        }
        // Grille 2 : sa colonne lumière en position 3 devient une colonne son vide ; elle attend son retour.
        #expect(show.grids[1].columns[3].kind == .audio)
        #expect(show.grids[1].columns[3].slots.allSatisfy { $0 == nil })
        #expect(show.grids[1].parkedColumns.map(\.index) == [3, 6, 7])
        #expect(show.grids[2].parkedColumns.map(\.index) == [6, 7])
        #expect(show.grids[0].parkedColumns.isEmpty)
        try show.validate()
    }

    @Test("Activer puis désactiver sans rien modifier redonne exactement le spectacle d'origine")
    func roundTrip() {
        let original = sample()
        var show = original
        let enabled = show.enableSharedLight(fromGrid: 0)
        #expect(enabled)
        show.disableSharedLight()
        #expect(show == original)
    }

    @Test("Désactiver : la grille d'origine garde les colonnes communes modifiées, les autres retrouvent les leurs")
    func disableKeepsEdits() {
        var show = sample()
        show.enableSharedLight(fromGrid: 0)
        show.grids[2][GridPosition(column: 7, row: 4)] = cuePad("Nouvelle")
        show.propagateSharedLight(from: 2)
        #expect(show.grids[1][GridPosition(column: 7, row: 4)]?.title == "Nouvelle")

        show.disableSharedLight()
        #expect(show.sharedLight == nil)
        #expect(show.grids[0][GridPosition(column: 7, row: 4)]?.title == "Nouvelle")
        #expect(show.grids[1][GridPosition(column: 7, row: 4)] == nil)
        #expect(show.grids[1][Self.cue]?.title == "Contre")
        #expect(show.grids[1].columns[3].kind == .light)
        #expect(show.grids[2][Self.cue]?.title == "pluie.wav")
        #expect(show.grids.allSatisfy { $0.parkedColumns.isEmpty })
        #expect(show.grids.map(\.lightChannel) == [1, 2, 3])
    }

    @Test("Les sons d'une colonne mise de côté restent dans le paquet")
    func parkedSoundsStayInPackage() {
        var show = sample()
        show.enableSharedLight(fromGrid: 0)
        #expect(show.usedAudioFileNames.contains("pluie.wav"))
    }

    @Test("Impossible sans colonne lumière dans la grille affichée")
    func needsLightColumns() {
        var show = sample()
        show.grids[0].columns[6] = Column.empty(name: "x", kind: .audio)
        show.grids[0].columns[7] = Column.empty(name: "y", kind: .audio)
        #expect(show.sharedLightActivationProblem(fromGrid: 0) != nil)
        let enabled = show.enableSharedLight(fromGrid: 0)
        #expect(!enabled)
        #expect(show.sharedLight == nil)
    }

    @Test("Les canaux des grilles évitent le canal commun ; changer le canal commun refuse un canal pris")
    func channels() {
        var show = sample()
        show.enableSharedLight(fromGrid: 0)
        #expect(show.firstFreeLightChannel() == 5)
        let taken = show.setSharedLightChannel(2)  // pris par la grille 2
        #expect(!taken)
        let free = show.setSharedLightChannel(9)
        #expect(free)
        #expect(show.sharedLight?.channel == 9)
        #expect(show.lightChannel(grid: 1, column: 6) == 9)
        #expect(show.lightChannel(grid: 1, column: 0) == 2)
    }

    @Test("Une grille neuve reçoit les colonnes communes ; ses autres colonnes lumière deviennent des colonnes son")
    func newGrid() {
        var show = sample()
        var first = show.grids[0]
        first.columns[6] = Column.empty(name: "x", kind: .audio)
        first.columns[3] = Column.empty(name: "L", kind: .light)
        show.grids[0] = first
        show.enableSharedLight(fromGrid: 0)  // colonnes communes : 3 et 7
        let added = show.adaptingNewGrid(.empty(name: "D"))
        #expect(added.columns[3] == show.grids[0].columns[3])
        #expect(added.columns[7] == show.grids[0].columns[7])
        #expect(added.columns[6].kind == .audio)  // lumière par défaut, mais pas commune
    }

    @Test("Écrire puis relire garde l'option et les colonnes mises de côté")
    func fileRoundTrip() throws {
        var show = sample()
        show.enableSharedLight(fromGrid: 0)
        let read = try ShowPackage.decodeMigrating(try ShowPackage.encode(show))
        #expect(read.show == show)
        #expect(read.lightPairingsReset.isEmpty)
    }

    @Test("Un ancien fichier, sans ces clés, s'ouvre option désactivée et sans colonne mise de côté")
    func legacyFile() throws {
        let data = try ShowPackage.encode(sample())
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("sharedLight"))
        #expect(!text.contains("parkedColumns"))
        let read = try ShowPackage.decode(data)
        #expect(read.sharedLight == nil)
    }

    @Test("Validation : canal commun pris par une grille, colonne commune qui n'est pas lumière, pad mis de côté dangereux")
    func validation() {
        var show = sample()
        show.enableSharedLight(fromGrid: 0)

        var duplicate = show
        duplicate.grids[1].lightChannel = 1
        #expect(throws: ShowValidationError.duplicateLightChannel(1)) { try duplicate.validate() }

        var wrongKind = show
        wrongKind.grids[1].columns[6] = Column.empty(name: "x", kind: .audio)
        #expect(throws: ShowValidationError.valueOutOfRange("colonnes lumière communes")) { try wrongKind.validate() }

        var unsafe = show
        unsafe.grids[2].parkedColumns[0].column.slots[0] = soundPad("../secret.wav")
        #expect(throws: ShowValidationError.unsafeFileName("../secret.wav")) { try unsafe.validate() }
    }
}
