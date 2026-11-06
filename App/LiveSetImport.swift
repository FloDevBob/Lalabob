import LalabobEngine
import SwiftUI
import UniformTypeIdentifiers

extension FocusedValues {
    /// Ouvre le sélecteur « Importer un Live Set Ableton » de la fenêtre active (commande du menu Fichier).
    @Entry var liveSetPicker: Binding<Bool>?
}

/// Import d'un Live Set Ableton : sélecteur (le fichier .als ou, mieux, le dossier du projet Live, pour que l'app puisse
/// lire les sons à côté), choix en cas de dépassement d'une grille, puis compte rendu.
struct LiveSetImportSupport: ViewModifier {
    @Environment(ShowController.self) private var controller
    @State private var choosing = false
    @State private var pending: LiveSetImportRequest?
    @State private var report: String?
    @State private var readError: String?

    private static let contentTypes: [UTType] = [.folder] + (UTType(filenameExtension: "als").map { [$0] } ?? [])

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.liveSetPicker, $choosing)
            .fileImporter(isPresented: $choosing, allowedContentTypes: Self.contentTypes) { result in
                if case .success(let url) = result { read(url) }
            }
            .confirmationDialog(
                "Ce Live Set dépasse une grille",
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                titleVisibility: .visible, presenting: pending
            ) { request in
                Button("Découper en plusieurs grilles") { run(request, .splitIntoGrids) }
                Button("Garder 6 pistes × 8 scènes") { run(request, .truncate) }
                Button("Annuler", role: .cancel) {}
            } message: { request in
                Text(
                    "\(request.audioTrackCount) pistes audio et \(request.sceneCount) scènes. "
                        + "Une grille contient 6 colonnes son et 8 lignes.")
            }
            .alert("Live Set importé", isPresented: Binding(get: { report != nil }, set: { if !$0 { report = nil } })) {
                Button("OK") { report = nil }
            } message: {
                Text(report ?? "")
            }
            .alert("Import impossible", isPresented: Binding(get: { readError != nil }, set: { if !$0 { readError = nil } })) {
                Button("OK") { readError = nil }
            } message: {
                Text(readError ?? "")
            }
    }

    private func read(_ url: URL) {
        do {
            let request = try AbletonImporter.read(at: url)
            if request.needsLayoutChoice { pending = request } else { run(request, .splitIntoGrids) }
        } catch {
            readError = (error as? AbletonImportError)?.message ?? "Le Live Set n'a pas pu être lu."
        }
    }

    private func run(_ request: LiveSetImportRequest, _ overflow: LiveSetOverflow) {
        if let finished = controller.importLiveSet(request, overflow: overflow) { report = finished.summary }
    }
}
