import Foundation
import LalabobEngine
import LalabobModel
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Document `.lalabob` (déclaré dans project.yml).
    nonisolated static let lalabobShow = UTType(exportedAs: "fr.flodevbob.lalabob.show")
}

/// Un spectacle ouvert : paquet `.lalabob` = `show.json` + `Audio/`.
///
/// SwiftUI lit et enregistre le document en arrière-plan ; le `ShowController` de la fenêtre vit sur le fil
/// principal. Le document garde donc une copie du spectacle (`mirror`) tenue à jour à chaque modification,
/// et un dossier de travail où se trouvent les sons (copiés à l'ouverture, ajoutés à l'import).
/// L'annulation (⌘Z) sert aussi à SwiftUI pour savoir que le document a changé et l'enregistrer tout seul.
nonisolated final class LalabobDocument: ReferenceFileDocument {
    typealias Snapshot = Show

    static var readableContentTypes: [UTType] { [.lalabobShow] }

    let mirror: ShowMirror
    /// Dossier de travail des sons (dans les caches de l'app), supprimé à la fermeture.
    let workingAudio: URL
    /// Sons utilisés par des pads mais absents du paquet (signalés à l'ouverture).
    let missingAudio: [String]
    /// Spectacle déjà enregistré : il s'ouvre verrouillé (prêt pour la scène) ; un nouveau s'ouvre déverrouillé.
    let opensLocked: Bool

    init() {
        mirror = ShowMirror(.new())
        workingAudio = Self.makeWorkingDirectory()
        missingAudio = []
        opensLocked = false
    }

    required init(configuration: ReadConfiguration) throws {
        let contents: ShowPackage.Contents
        do {
            contents = try ShowPackage.read(configuration.file)
        } catch {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedFailureReasonErrorKey: Self.describe(error)])
        }
        let directory = Self.makeWorkingDirectory()
        if let audio = ShowPackage.audioFolder(of: configuration.file) {
            for name in contents.audioFileNames {
                try? audio.fileWrappers?[name]?.write(
                    to: directory.appending(path: name), options: [], originalContentsURL: nil)
            }
        }
        mirror = ShowMirror(contents.show)
        workingAudio = directory
        missingAudio = contents.missingAudio
        opensLocked = true
    }

    func snapshot(contentType: UTType) throws -> Show {
        mirror.current
    }

    /// Réécrit `show.json` et ajoute au dossier `Audio/` du paquet les sons importés depuis le dernier enregistrement
    /// (les sons déjà présents ne sont pas recopiés).
    func fileWrapper(snapshot: Show, configuration: WriteConfiguration) throws -> FileWrapper {
        let existing = configuration.existingFile.flatMap(ShowPackage.audioFolder(of:))
        let present = Set(existing?.fileWrappers?.keys.map { $0 } ?? [])
        var added: [String: FileWrapper] = [:]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: workingAudio.path)) ?? []
        for name in names where !present.contains(name) && AudioClip.isSafeFileName(name) {
            if let file = try? FileWrapper(url: workingAudio.appending(path: name), options: []) { added[name] = file }
        }
        return try ShowPackage.wrapper(for: snapshot, audio: existing, adding: added)
    }

    deinit {
        try? FileManager.default.removeItem(at: workingAudio.deletingLastPathComponent())
    }

    private static func makeWorkingDirectory() -> URL {
        let url = URL.cachesDirectory.appending(path: "Spectacles ouverts/\(UUID().uuidString)/Audio", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func describe(_ error: ShowPackageError) -> String {
        switch error {
        case .notAPackage: "Ce fichier n'est pas un spectacle Lalabob."
        case .missingShowFile: "Le fichier show.json est absent."
        case .corrupt: "Le fichier show.json est illisible."
        case .tooLarge: "Le fichier show.json est anormalement gros."
        case .invalid(let reason): "Le spectacle contient des données invalides (\(reason))."
        }
    }
}

extension EnvironmentValues {
    /// La session MIDI de l'app (absente si CoreMIDI n'a pas pu démarrer).
    @Entry var midiSession: ControllerSession?
}

/// Une fenêtre de spectacle : crée son `ShowController` (et donc son moteur audio), le rattache au contrôleur
/// MIDI quand elle devient active, et l'en détache à la fermeture.
struct DocumentWindow: View {
    let document: LalabobDocument
    @Environment(\.midiSession) private var midiSession
    @Environment(\.appearsActive) private var appearsActive
    @State private var controller: ShowController?
    @State private var showsMissingAudio = false

    var body: some View {
        Group {
            if let controller {
                ContentView()
                    .environment(controller)
                    .task { await controller.observePlayback() }
                    .task { await controller.observeOutputDevices() }
            } else {
                Color.clear
            }
        }
        .onAppear {
            if controller == nil {
                let created = ShowController.live(
                    show: document.mirror.current, audioDirectory: document.workingAudio, isLocked: document.opensLocked)
                let mirror = document.mirror
                created.onShowChange = { mirror.update($0) }
                controller = created
                showsMissingAudio = !document.missingAudio.isEmpty
            }
            attachIfActive()
        }
        .onChange(of: appearsActive) { attachIfActive() }
        .onDisappear {
            if let controller { midiSession?.detach(controller) }
        }
        .alert("Sons manquants", isPresented: $showsMissingAudio) {
            Button("OK") {}
        } message: {
            Text("Ces sons sont introuvables dans le spectacle ; leurs pads restent muets :\n" + document.missingAudio.joined(separator: ", "))
        }
    }

    private func attachIfActive() {
        guard appearsActive, let controller else { return }
        midiSession?.attach(controller)
    }
}
