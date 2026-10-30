import Foundation
import LalabobModel
import Testing

@testable import LalabobEngine

@MainActor
@Suite("Import de sons", .serialized)
struct AudioImportTests {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "lalabob-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(_ name: String, in dir: URL, bytes: [UInt8] = [1, 2, 3]) throws -> URL {
        let url = dir.appending(path: name)
        try Data(bytes).write(to: url)
        return url
    }

    @Test func importCopiesTheFileUnderASafeName() throws {
        let source = try tempDir()
        let library = try tempDir()
        let file = try makeFile("Rire du public.wav", in: source)

        let name = try AudioImporter.importFile(at: file, into: library)
        #expect(name == "Rire du public.wav")
        #expect(FileManager.default.fileExists(atPath: library.appending(path: name).path))
        #expect(FileManager.default.fileExists(atPath: file.path))  // l'original n'est pas déplacé
    }

    @Test func importingTheSameFileTwiceReusesIt() throws {
        let source = try tempDir()
        let library = try tempDir()
        let file = try makeFile("gong.aif", in: source)
        let first = try AudioImporter.importFile(at: file, into: library)
        let second = try AudioImporter.importFile(at: file, into: library)
        #expect(first == second)
        #expect(try FileManager.default.contentsOfDirectory(atPath: library.path).count == 1)
    }

    @Test func aDifferentFileWithTheSameNameGetsANumber() throws {
        let library = try tempDir()
        let first = try makeFile("gong.aif", in: try tempDir(), bytes: [1])
        let second = try makeFile("gong.aif", in: try tempDir(), bytes: [2, 2])
        #expect(try AudioImporter.importFile(at: first, into: library) == "gong.aif")
        #expect(try AudioImporter.importFile(at: second, into: library) == "gong 2.aif")
    }

    @Test func nonAudioFilesAreRefused() throws {
        let file = try makeFile("notes.txt", in: try tempDir())
        #expect(throws: AudioImportError.unsupportedFormat) { try AudioImporter.importFile(at: file, into: try tempDir()) }
    }

    @Test func folderIsRefused() throws {
        let folder = try tempDir().appending(path: "dossier.wav")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(throws: AudioImportError.notAFile) { try AudioImporter.importFile(at: folder, into: try tempDir()) }
    }

    @Test func padFromAFileIsPrefilled() {
        let pad = AudioImporter.pad(forFileName: "Porte qui grince.wav")
        #expect(pad.title == "Porte qui grince")
        guard case .audio(let clip) = pad.content else {
            Issue.record("pad audio attendu")
            return
        }
        #expect(clip.fileName == "Porte qui grince.wav")
        // La couleur proposée est stable : le même nom donne la même teinte.
        #expect(AudioImporter.pad(forFileName: "Porte qui grince.wav").tint == pad.tint)
    }

    @Test func droppingAFileOnAPadImportsAndPlacesIt() throws {
        let library = try tempDir()
        let file = try makeFile("rire.wav", in: try tempDir())
        let controller = ShowController(
            audioDirectory: library, defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.undoManager = undo

        #expect(controller.dropAudioFile(file, at: GridPosition(column: 0, row: 0)))
        #expect(controller.pad(at: GridPosition(column: 0, row: 0))?.title == "rire")
        #expect(!controller.dropAudioFile(file, at: GridPosition(column: 6, row: 0)))  // pas dans la lumière
        undo.undo()
        #expect(controller.pad(at: GridPosition(column: 0, row: 0)) == nil)
    }

    @Test func aFailedDropIsReportedInsteadOfIgnored() throws {
        let library = try tempDir()
        let text = try makeFile("notes.txt", in: try tempDir())
        let controller = ShowController(
            audioDirectory: library, defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)

        #expect(!controller.dropAudioFile(text, at: GridPosition(column: 0, row: 0)))
        #expect(controller.importError?.contains("notes.txt") == true)
        controller.dismissImportError()
        #expect(controller.importError == nil)

        // Un dépôt réussi n'affiche rien.
        let sound = try makeFile("rire.wav", in: try tempDir())
        #expect(controller.dropAudioFile(sound, at: GridPosition(column: 0, row: 0)))
        #expect(controller.importError == nil)
    }

    @Test func librarySelection() async throws {
        let dir = try tempDir()
        _ = try makeFile("rire.wav", in: dir)
        let library = LibraryController(defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!, securityScoped: false)
        await library.addFavorite(dir)
        let item = try #require(library.visibleItems.first)
        library.selectItem(item.id)
        #expect(library.selectedItem == item.id)
        // Changer de dossier efface la sélection.
        await library.addFavorite(try tempDir())
        #expect(library.selectedItem == nil)
    }
}
