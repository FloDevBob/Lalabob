import Foundation
import LalabobImport
import LalabobModel
import Testing

@testable import LalabobEngine

@MainActor
@Suite("Import d'un Live Set Ableton", .serialized)
struct LiveSetImportTests {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "lalabob-liveset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func clipXML(name: String, relative: String = "", absolute: String = "") -> String {
        """
        <ClipSlot><ClipSlot><Value><AudioClip><Name Value="\(name)"/><Loop><LoopOn Value="true"/></Loop>
        <SampleRef><FileRef><RelativePath Value="\(relative)"/><Path Value="\(absolute)"/></FileRef></SampleRef>
        </AudioClip></Value></ClipSlot></ClipSlot>
        """
    }

    /// `.als` minimal : une piste audio, deux clips.
    private func liveSetXML(_ clips: [String]) -> String {
        """
        <Ableton Creator="Ableton Live 12.0"><LiveSet><Tracks><AudioTrack>
        <Name><UserName Value="Sons"/></Name>
        <DeviceChain><MainSequencer><ClipSlotList>\(clips.joined())</ClipSlotList></MainSequencer></DeviceChain>
        </AudioTrack></Tracks><Scenes><Scene/><Scene/></Scenes></LiveSet></Ableton>
        """
    }

    private func gzip(_ text: String) throws -> Data {
        let raw = Data(text.utf8)
        let deflated = try (raw as NSData).compressed(using: .zlib) as Data
        var out = Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3]) + deflated + Data([0, 0, 0, 0])
        let size = UInt32(raw.count)
        out.append(contentsOf: [UInt8(size & 0xFF), UInt8((size >> 8) & 0xFF), UInt8((size >> 16) & 0xFF), UInt8((size >> 24) & 0xFF)])
        return out
    }

    /// Dossier de projet : `Projet/Test.als` et `Projet/Samples/rire.wav`.
    private func makeProject(clips: [String]) throws -> (folder: URL, liveSet: URL) {
        let folder = try tempDir().appending(path: "Projet")
        try FileManager.default.createDirectory(at: folder.appending(path: "Samples"), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: folder.appending(path: "Samples/rire.wav"))
        let liveSet = folder.appending(path: "Test.als")
        try gzip(liveSetXML(clips)).write(to: liveSet)
        return (folder, liveSet)
    }

    private func makeController() throws -> ShowController {
        ShowController(
            audioDirectory: try tempDir(), defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
    }

    @Test("Un dossier de projet désigne son unique .als ; plusieurs .als ou aucun : refusé")
    func locatesTheLiveSet() throws {
        let project = try makeProject(clips: [])
        // Le dossier temporaire passe par un lien symbolique (/var → /private/var) : on compare les chemins résolus.
        #expect(
            try AbletonImporter.locateLiveSet(at: project.folder).resolvingSymlinksInPath()
                == project.liveSet.resolvingSymlinksInPath())
        #expect(try AbletonImporter.locateLiveSet(at: project.liveSet) == project.liveSet)

        try Data().write(to: project.folder.appending(path: "Autre.als"))
        #expect(throws: AbletonImportError.severalLiveSetsInFolder(["Autre.als", "Test.als"])) {
            try AbletonImporter.locateLiveSet(at: project.folder)
        }
        #expect(throws: AbletonImportError.noLiveSetInFolder) { try AbletonImporter.locateLiveSet(at: try tempDir()) }
        #expect(throws: AbletonImportError.notALiveSet) { try AbletonImporter.locateLiveSet(at: project.folder.appending(path: "Samples/rire.wav")) }
    }

    @Test("Les sons sont retrouvés par chemin relatif, puis absolu, puis par nom")
    func findsSamples() throws {
        let project = try makeProject(clips: [])
        let elsewhere = try tempDir().appending(path: "ailleurs.wav")
        try Data([9]).write(to: elsewhere)
        func ref(_ rel: String, _ abs: String, _ name: String) -> AbletonSampleReference {
            AbletonSampleReference(relativePath: rel, absolutePath: abs, fileName: name)
        }
        #expect(AbletonImporter.sampleURL(for: ref("Samples/rire.wav", "", "rire.wav"), liveSetFolder: project.folder)?.lastPathComponent == "rire.wav")
        #expect(AbletonImporter.sampleURL(for: ref("", elsewhere.path, "ailleurs.wav"), liveSetFolder: project.folder)?.path == elsewhere.path)
        #expect(AbletonImporter.sampleURL(for: ref("Deplace/rire.wav", "/nulle/part/rire.wav", "rire.wav"), liveSetFolder: project.folder) != nil)  // par nom
        #expect(AbletonImporter.sampleURL(for: ref("Samples/absent.wav", "", "absent.wav"), liveSetFolder: project.folder) == nil)
    }

    @Test("Le chemin relatif d'un vrai projet Live remonte hors du dossier (« ../../Sons/x.wav ») et reste lisible")
    func relativePathMayLeaveTheProject() throws {
        let root = try tempDir()
        let project = root.appending(path: "Musique/Mon Projet")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "Sons"), withIntermediateDirectories: true)
        try Data([7]).write(to: root.appending(path: "Sons/gong.wav"))
        let reference = AbletonSampleReference(relativePath: "../../Sons/gong.wav", absolutePath: "/nulle/part/gong.wav", fileName: "gong.wav")
        #expect(AbletonImporter.sampleURL(for: reference, liveSetFolder: project)?.lastPathComponent == "gong.wav")
    }

    @Test("Un dossier qui contient le projet (et les sons) désigne l'unique .als de ses sous-dossiers, sans lire Backup")
    func locatesTheLiveSetInASubfolder() throws {
        let project = try makeProject(clips: [])
        let parent = project.folder.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: project.folder.appending(path: "Backup"), withIntermediateDirectories: true)
        try Data().write(to: project.folder.appending(path: "Backup/Test [2024].als"))
        #expect(try AbletonImporter.locateLiveSet(at: parent) == project.liveSet)

        let other = parent.appending(path: "Autre Projet")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data().write(to: other.appending(path: "Autre.als"))
        #expect(throws: AbletonImportError.severalLiveSetsInFolder(["Autre Projet/Autre.als", "Projet/Test.als"])) {
            try AbletonImporter.locateLiveSet(at: parent)
        }
    }

    @Test("Le dossier choisi sert aussi de dossier de recherche par nom (sons hors du projet)")
    func searchesThePickedFolder() throws {
        let root = try tempDir()
        let project = root.appending(path: "Projet")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "Vrac/Sous"), withIntermediateDirectories: true)
        try Data([5]).write(to: root.appending(path: "Vrac/Sous/cloche.wav"))
        let reference = AbletonSampleReference(relativePath: "Samples/cloche.wav", absolutePath: "", fileName: "cloche.wav")
        #expect(AbletonImporter.sampleURL(for: reference, liveSetFolder: project) == nil)
        #expect(AbletonImporter.sampleURL(for: reference, liveSetFolder: project, searchRoots: [root])?.lastPathComponent == "cloche.wav")
    }

    @Test("Importer : grille ajoutée et sélectionnée, son copié, pad muet pour le son manquant, un seul ⌘Z")
    func importsAndUndoes() throws {
        let project = try makeProject(clips: [
            clipXML(name: "Rire", relative: "Samples/rire.wav"),
            clipXML(name: "Perdu", relative: "Samples/perdu.wav", absolute: "/nulle/part/perdu.wav"),
        ])
        let controller = try makeController()
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.undoManager = undo

        let request = try AbletonImporter.read(at: project.folder)
        #expect(request.name == "Test")
        #expect(request.audioTrackCount == 1)
        #expect(!request.needsLayoutChoice)

        let report = try #require(controller.importLiveSet(request, overflow: .splitIntoGrids))
        #expect(report.importedClips == 2)
        #expect(report.missingSamples == ["perdu.wav"])
        #expect(controller.show.grids.count == 2)  // la grille vide d'origine + celle du Live Set
        #expect(controller.selectedGridIndex == 1)
        let grid = controller.show.grids[1]
        #expect(grid.name == "Test")
        #expect(grid.columns[0].name == "Sons")
        let first = try #require(grid[GridPosition(column: 0, row: 0)])
        guard case .audio(let clip) = first.content else { Issue.record("pad son attendu"); return }
        #expect(clip.fileName == "rire.wav")
        #expect(clip.loops)
        #expect(FileManager.default.fileExists(atPath: try #require(controller.audioDirectory).appending(path: "rire.wav").path))
        try controller.show.validate()

        undo.undo()
        #expect(controller.show.grids.count == 1)
    }

    @Test("Spectacle verrouillé : rien n'est importé")
    func refusedWhenLocked() throws {
        let project = try makeProject(clips: [clipXML(name: "Rire", relative: "Samples/rire.wav")])
        let controller = try makeController()
        controller.isLocked = true
        let request = try AbletonImporter.read(at: project.liveSet)
        #expect(controller.importLiveSet(request, overflow: .truncate) == nil)
        #expect(controller.show.grids.count == 1)
    }

    @Test("Live Set sans clip audio : message clair, rien d'ajouté")
    func nothingToImport() throws {
        let project = try makeProject(clips: [])
        let controller = try makeController()
        let request = try AbletonImporter.read(at: project.liveSet)
        #expect(controller.importLiveSet(request, overflow: .splitIntoGrids) == nil)
        #expect(controller.importError != nil)
        #expect(controller.show.grids.count == 1)
    }
}
