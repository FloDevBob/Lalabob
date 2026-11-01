import Foundation
import Testing

@testable import LalabobEngine

@Suite("Poids des sons")
struct AudioFolderUsageTests {
    private func folder(_ files: [String: Int]) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "usage-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, size) in files { try Data(count: size).write(to: url.appending(path: name)) }
        return url
    }

    @Test("Les sons utilisés et inutilisés sont comptés à part")
    func splitsUsedAndUnused() throws {
        let url = try folder(["a.wav": 100, "b.wav": 50, "vieux.wav": 30])
        defer { try? FileManager.default.removeItem(at: url) }
        let usage = AudioFolderUsage.measure(directory: url, used: ["a.wav", "b.wav"])
        #expect(usage == AudioFolderUsage(usedCount: 2, usedBytes: 150, unusedCount: 1, unusedBytes: 30))
    }

    @Test("Un dossier absent ou vide donne zéro")
    func emptyOrMissing() throws {
        let missing = URL.temporaryDirectory.appending(path: "absent-\(UUID().uuidString)")
        #expect(AudioFolderUsage.measure(directory: missing, used: ["a.wav"]) == .empty)
    }

    @Test("Un son utilisé mais absent du dossier n'est pas compté")
    func usedButMissing() throws {
        let url = try folder(["a.wav": 10])
        defer { try? FileManager.default.removeItem(at: url) }
        let usage = AudioFolderUsage.measure(directory: url, used: ["a.wav", "fantome.wav"])
        #expect(usage.usedCount == 1)
    }

    @Test("Le résumé mentionne les sons inutilisés seulement s'il y en a")
    func summaryMentionsUnusedOnlyWhenAny() {
        let clean = AudioFolderUsage(usedCount: 2, usedBytes: 1000, unusedCount: 0, unusedBytes: 0)
        #expect(clean.summary.hasPrefix("Sons : 2 fichiers"))
        #expect(!clean.summary.contains("inutilisé"))
        let dirty = AudioFolderUsage(usedCount: 1, usedBytes: 1000, unusedCount: 3, unusedBytes: 5000)
        #expect(dirty.summary.contains("3 fichiers inutilisés"))
        #expect(dirty.summary.contains("enregistrement"))
    }
}
