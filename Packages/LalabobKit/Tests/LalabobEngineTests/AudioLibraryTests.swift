import AVFoundation
import Foundation
import LalabobModel
import Testing

@testable import LalabobEngine

@MainActor
@Suite("Bibliothèque de sons", .serialized)
struct AudioLibraryTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "lalabob-library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Fichier WAV de `seconds` secondes (silence).
    private func writeWAV(_ name: String, in dir: URL, seconds: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
        let frames = AVAudioFrameCount(seconds * 8000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let file = try AVAudioFile(forWriting: dir.appending(path: name), settings: format.settings)
        try file.write(from: buffer)
    }

    @Test func listsOnlyAudioFilesSortedWithDurations() async throws {
        let dir = try folder()
        try writeWAV("b.wav", in: dir, seconds: 2)
        try writeWAV("A10.wav", in: dir, seconds: 1)
        try writeWAV("A2.wav", in: dir, seconds: 1)
        try Data("x".utf8).write(to: dir.appending(path: "notes.txt"))
        try FileManager.default.createDirectory(at: dir.appending(path: "dossier.wav"), withIntermediateDirectories: true)

        let items = await AudioLibrary.items(in: dir)
        #expect(items.map(\.name) == ["A2.wav", "A10.wav", "b.wav"])  // tri « naturel »
        #expect(abs((items.last?.duration ?? 0) - 2) < 0.01)
    }

    @Test func unreadableAudioFileHasNoDuration() async throws {
        let dir = try folder()
        try Data("pas un son".utf8).write(to: dir.appending(path: "faux.wav"))
        let items = await AudioLibrary.items(in: dir)
        #expect(items.count == 1)
        #expect(items.first?.duration == nil)
    }

    @Test func searchIgnoresCaseAndAccents() {
        let items = ["Générique.wav", "Porte.wav", "genou.mp3"].map {
            AudioLibraryItem(url: URL(filePath: "/tmp/\($0)"), name: $0, duration: nil)
        }
        #expect(AudioLibrary.filter(items, query: "gene").map(\.name) == ["Générique.wav"])
        #expect(AudioLibrary.filter(items, query: "GEN").count == 2)
        #expect(AudioLibrary.filter(items, query: "  ").count == 3)
    }

    @Test(arguments: [(0.0, "0:00"), (4.4, "0:04"), (62.0, "1:02"), (3725.0, "1:02:05")])
    func durationFormatting(seconds: Double, expected: String) {
        #expect(AudioLibrary.formatDuration(seconds) == expected)
    }

    @Test func favoritesArePersistedAndRestored() async throws {
        let defaults = UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!
        let dir = try folder()
        try writeWAV("rire.wav", in: dir, seconds: 1)

        let library = LibraryController(defaults: defaults, securityScoped: false)
        await library.addFavorite(dir)
        #expect(library.favorites.map(\.name) == [dir.lastPathComponent])
        #expect(library.currentFavorite == library.favorites.first?.id)
        #expect(library.visibleItems.map(\.name) == ["rire.wav"])

        let restored = LibraryController(defaults: defaults, securityScoped: false)
        #expect(restored.favorites.map(\.url.standardizedFileURL) == [dir.standardizedFileURL])
    }

    @Test func addingTheSameFolderTwiceKeepsOneFavorite() async throws {
        let defaults = UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!
        let dir = try folder()
        let library = LibraryController(defaults: defaults, securityScoped: false)
        await library.addFavorite(dir)
        await library.addFavorite(dir)
        #expect(library.favorites.count == 1)
    }

    @Test func removingAFavorite() async throws {
        let defaults = UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!
        let library = LibraryController(defaults: defaults, securityScoped: false)
        await library.addFavorite(try folder())
        let id = try #require(library.favorites.first?.id)
        library.removeFavorite(id)
        #expect(library.favorites.isEmpty)
        #expect(library.currentFavorite == nil)
        #expect(library.visibleItems.isEmpty)
        #expect(LibraryController(defaults: defaults, securityScoped: false).favorites.isEmpty)
    }

    @Test func aFolderThatDisappearedIsDropped() async throws {
        let defaults = UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!
        let dir = try folder()
        let library = LibraryController(defaults: defaults, securityScoped: false)
        await library.addFavorite(dir)
        try FileManager.default.removeItem(at: dir)
        #expect(LibraryController(defaults: defaults, securityScoped: false).favorites.isEmpty)
    }
}

@MainActor
@Suite("Libellés de la grille")
struct GridLabelTests {
    @Test func soundCountPerGrid() {
        var grid = PadGrid.empty(name: "G")
        grid.columns[0].slots[0] = Pad(title: "a", tint: .vert, content: .audio(clip: AudioClip(fileName: "a.wav")))
        grid.columns[1].slots[2] = Pad(title: "b", tint: .vert, content: .audio(clip: AudioClip(fileName: "b.wav")))
        let controller = ShowController(show: Show(name: "S", grids: [grid, .empty(name: "H")]))
        #expect(controller.padCount(inGrid: 0) == 2)
        #expect(controller.padCount(inGrid: 1) == 0)
        #expect(controller.padCount(inGrid: 9) == 0)
    }

    @Test func positionLabelUsesTheColumnNameAndTheControllerNote() {
        let controller = ShowController(
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        let position = GridPosition(column: 2, row: 5)
        #expect(controller.positionLabel(for: position) == "Colonne 3 · ligne 6")
        controller.setConnectedController(.launchpadX)
        // Launchpad : rangée 3 depuis le bas → (2 + 1) × 10 + 3 = 33.
        #expect(controller.positionLabel(for: position) == "Colonne 3 · ligne 6 · note 33")
    }

    @Test func usesAudioFile() {
        var grid = PadGrid.empty(name: "G")
        grid.columns[0].slots[0] = Pad(title: "a", tint: .vert, content: .audio(clip: AudioClip(fileName: "rire.wav")))
        let controller = ShowController(show: Show(name: "S", grids: [.empty(name: "x"), grid]))
        #expect(controller.usesAudioFile(named: "rire.wav"))  // dans n'importe quelle grille
        #expect(!controller.usesAudioFile(named: "porte.wav"))
    }
}
