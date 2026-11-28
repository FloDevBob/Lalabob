import Foundation
import LalabobModel
import Testing

@testable import LalabobEngine

/// Spectacle d'entraînement du tutoriel : embarqué dans l'app, ouvert en copie neuve (Aide ▸ Ouvrir le spectacle
/// d'entraînement) pour qu'on puisse tout essayer sans abîmer l'original.
@Suite("Spectacle d'entraînement")
struct TrainingShowTests {
    /// Le spectacle livré avec l'app (docs/tutoriel), retrouvé depuis ce fichier de test.
    static let bundledShow = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/tutoriel/Entrainement.lalabob")

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "lalabob-training-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Un petit paquet `.lalabob` valide, pour ne pas dépendre du vrai spectacle.
    private func makeSource(in directory: URL) throws -> URL {
        var grid = PadGrid.empty(name: "G")
        grid.columns[0].slots[0] = .sound(title: "Pluie", tint: .azur, clip: AudioClip(fileName: "pluie.m4a", loops: true))
        let show = Show(name: "Entraînement", grids: [grid])
        let sound = FileWrapper(regularFileWithContents: Data("son".utf8))
        let package = try ShowPackage.wrapper(for: show, audio: nil, adding: ["pluie.m4a": sound])
        let url = directory.appending(path: "Source.lalabob")
        try package.write(to: url, options: .atomic, originalContentsURL: nil)
        return url
    }

    @Test func copyIsNamedForTheWindowTitleAndReadsBack() throws {
        let directory = try temporaryDirectory()
        let source = try makeSource(in: directory)
        let copy = try TrainingShow.freshCopy(of: source, in: directory.appending(path: "copies"))
        #expect(copy.lastPathComponent == "Entraînement.lalabob")
        let contents = try ShowPackage.read(FileWrapper(url: copy))
        #expect(contents.show.name == "Entraînement")
        #expect(contents.missingAudio.isEmpty)
    }

    @Test func eachCopyIsNewAndTheSourceIsUntouched() throws {
        let directory = try temporaryDirectory()
        let source = try makeSource(in: directory)
        let parent = directory.appending(path: "copies")
        let first = try TrainingShow.freshCopy(of: source, in: parent)
        // Abîmer la première copie, comme pendant un exercice.
        try Data("{}".utf8).write(to: first.appending(path: ShowPackage.showFileName))
        let second = try TrainingShow.freshCopy(of: source, in: parent)
        #expect(first != second)
        #expect(throws: Never.self) { try ShowPackage.read(FileWrapper(url: second)) }
        #expect(throws: Never.self) { try ShowPackage.read(FileWrapper(url: source)) }
    }

    @Test func missingSourceThrows() throws {
        let directory = try temporaryDirectory()
        #expect(throws: (any Error).self) {
            try TrainingShow.freshCopy(of: directory.appending(path: "absent.lalabob"), in: directory)
        }
    }

    /// Le vrai spectacle livré : il s'ouvre (décodage + validation), aucun son ne manque, et le module 1 y trouve
    /// les pads qu'il cite, au bon endroit, avec les boucles annoncées.
    @Test func bundledShowMatchesModuleOne() throws {
        let contents = try ShowPackage.read(FileWrapper(url: Self.bundledShow))
        #expect(contents.missingAudio.isEmpty)
        let grid = try #require(contents.show.grids.first)
        #expect(grid.columns[0].name == "Ambiances")
        #expect(grid.columns[1].name == "Bruitages")
        #expect(grid.columns[0].slots[0]?.title == "Pluie")
        #expect(grid.columns[0].slots[0]?.audio?.loops == true)
        #expect(grid.columns[0].slots[1]?.title == "Vent dans les arbres")
        #expect(grid.columns[0].slots[1]?.audio?.loops == true)
        #expect(grid.columns[1].slots[0]?.title == "Tonnerre")
        #expect(grid.columns[1].slots[0]?.audio?.loops == false)
        #expect(grid.columns[1].slots[1]?.title == "Porte qui claque")
    }
}
