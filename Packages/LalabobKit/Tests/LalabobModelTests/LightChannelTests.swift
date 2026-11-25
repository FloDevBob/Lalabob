import Foundation
import Testing

@testable import LalabobModel

/// Un canal LightKey par grille (fiche 01) : attribution, migration des anciens fichiers, validation.
@Suite("Canal LightKey par grille")
struct LightChannelTests {
    private static let cueCell = GridPosition(column: 6, row: 0)

    private func pairedCue() -> Pad {
        Pad(
            title: "Face", tint: .blanc,
            light: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0), isPaired: true))
    }

    /// Un spectacle de `count` grilles, chacune avec une cue appairée et un fader lumière appairé.
    private func pairedShow(grids count: Int) -> Show {
        var show = Show.new(name: "S")
        show.grids = (0..<count).map { index in
            var grid = PadGrid.empty(name: "G\(index + 1)")
            grid[Self.cueCell] = pairedCue()
            grid.columns[7].isFaderPaired = true
            return grid
        }
        return show
    }

    /// Le JSON tel qu'une version d'avant le canal par grille l'écrivait : sans aucune clé `lightChannel`.
    private func legacyJSON(_ show: Show) throws -> Data {
        let data = try ShowPackage.encode(show)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let grids = try #require(object["grids"] as? [[String: Any]])
        object["grids"] = grids.map { grid in
            var grid = grid
            grid.removeValue(forKey: "lightChannel")
            return grid
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func isPaired(_ show: Show, grid: Int) -> Bool {
        show.grids[grid][Self.cueCell]?.light?.isPaired == true
    }

    // MARK: Attribution

    @Test("Un nouveau spectacle : la grille 1 est sur le canal 1")
    func newShow() {
        #expect(Show.new().grids[0].lightChannel == 1)
    }

    @Test("Un spectacle construit en mémoire : chaque grille reçoit son canal, dans l'ordre")
    func initAssignsChannels() {
        let show = Show(name: "S", grids: [.empty(name: "A"), .empty(name: "B"), .empty(name: "C")])
        #expect(show.grids.map(\.lightChannel) == [1, 2, 3])
    }

    @Test("Premier canal libre, en sautant ceux déjà pris")
    func firstFreeChannel() {
        var show = Show(name: "S", grids: [.empty(name: "A"), .empty(name: "B")])
        show.grids[0].lightChannel = 2
        show.grids[1].lightChannel = 1
        #expect(show.firstFreeLightChannel() == 3)
        show.grids[1].lightChannel = nil
        #expect(show.firstFreeLightChannel() == 1)
    }

    @Test("Les 16 canaux pris : plus de canal libre")
    func noFreeChannel() {
        let show = Show(name: "S", grids: (1...16).map { PadGrid.empty(name: "G\($0)") })
        #expect(show.grids.map(\.lightChannel) == (1...16).map { Optional($0) })
        #expect(show.firstFreeLightChannel() == nil)
    }

    @Test("Au-delà de 16 grilles, les suivantes sont « Sans canal »")
    func beyondSixteen() {
        let show = Show(name: "S", grids: (1...17).map { PadGrid.empty(name: "G\($0)") })
        #expect(show.grids[15].lightChannel == 16)
        #expect(show.grids[16].lightChannel == nil)
    }

    // MARK: Fichiers

    @Test("Le canal est écrit, y compris « Sans canal », et relu à l'identique")
    func roundTrip() throws {
        var show = Show(name: "S", grids: [.empty(name: "A"), .empty(name: "B")])
        show.grids[1].lightChannel = nil
        let data = try ShowPackage.encode(show)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"lightChannel\" : 1"))
        #expect(text.contains("\"lightChannel\" : null"))
        let read = try ShowPackage.decodeMigrating(data)
        #expect(read.show == show)
        #expect(read.lightPairingsReset.isEmpty)
    }

    @Test("Ancien fichier : grille N → canal N, appairages des grilles 2 et suivantes remis à faux, grille 1 intacte")
    func migration() throws {
        let read = try ShowPackage.decodeMigrating(try legacyJSON(pairedShow(grids: 3)))
        #expect(read.show.grids.map(\.lightChannel) == [1, 2, 3])
        #expect(read.lightPairingsReset == [1, 2])
        #expect(isPaired(read.show, grid: 0))
        #expect(read.show.grids[0].columns[7].isFaderPaired)
        #expect(!isPaired(read.show, grid: 1))
        #expect(!read.show.grids[1].columns[7].isFaderPaired)
        #expect(!isPaired(read.show, grid: 2))
    }

    @Test("Ancien fichier sans aucun appairage : rien à signaler")
    func migrationWithoutPairings() throws {
        let show = Show(name: "S", grids: [.empty(name: "A"), .empty(name: "B")])
        let read = try ShowPackage.decodeMigrating(try legacyJSON(show))
        #expect(read.show.grids.map(\.lightChannel) == [1, 2])
        #expect(read.lightPairingsReset.isEmpty)
    }

    @Test("Ancien paquet : la lecture signale les grilles à réappairer")
    func packageReportsResets() throws {
        let showFile = FileWrapper(regularFileWithContents: try legacyJSON(pairedShow(grids: 2)))
        let package = FileWrapper(directoryWithFileWrappers: [ShowPackage.showFileName: showFile])
        let read = try ShowPackage.read(package)
        #expect(read.lightPairingsReset == [1])
        #expect(read.show.grids[1].lightChannel == 2)
    }

    @Test("Ancien fichier de 17 grilles : la 17e est « Sans canal »")
    func migrationBeyondSixteen() throws {
        let show = Show(name: "S", grids: (1...17).map { PadGrid.empty(name: "G\($0)") })
        let read = try ShowPackage.decodeMigrating(try legacyJSON(show))
        #expect(read.show.grids[16].lightChannel == nil)
    }

    // MARK: Validation

    @Test("Deux grilles sur le même canal : refusé")
    func duplicateChannel() {
        var show = Show(name: "S", grids: [.empty(name: "A"), .empty(name: "B")])
        show.grids[1].lightChannel = 1
        #expect(throws: ShowValidationError.duplicateLightChannel(1)) { try show.validate() }
    }

    @Test("Canal hors de 1…16 : refusé")
    func channelOutOfRange() {
        var show = Show.new()
        show.grids[0].lightChannel = 17
        #expect(throws: ShowValidationError.valueOutOfRange("canal LightKey")) { try show.validate() }
        show.grids[0].lightChannel = 0
        #expect(throws: ShowValidationError.valueOutOfRange("canal LightKey")) { try show.validate() }
    }

    @Test("Plusieurs grilles « Sans canal » : accepté")
    func severalWithoutChannel() throws {
        var show = Show(name: "S", grids: [.empty(name: "A"), .empty(name: "B")])
        show.grids[0].lightChannel = nil
        show.grids[1].lightChannel = nil
        try show.validate()
    }
}
