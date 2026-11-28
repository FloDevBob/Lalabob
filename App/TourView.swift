import AppKit
import LalabobDesign
import LalabobEngine
import SwiftUI
import WebKit

/// La visite guidée et le spectacle d'entraînement, livrés dans l'app : le dossier `visite` (copie de
/// `docs/tutoriel/visite`, la même page que celle publiée en ligne) et `Entrainement.lalabob`.
enum Tour {
    /// Identifiant de la fenêtre « Visite guidée ».
    static let windowID = "tour"

    /// La page de la visite (hors ligne) ; ses sons sont dans `sons.js`, à côté.
    static var page: URL? {
        guard let url = Bundle.main.url(forResource: "visite", withExtension: nil)?.appending(path: "index.html"),
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    /// Le spectacle d'entraînement d'origine, jamais ouvert directement : on en ouvre une copie neuve.
    static var trainingShow: URL? { Bundle.main.url(forResource: "Entrainement", withExtension: "lalabob") }

    /// Ouvre une copie neuve du spectacle d'entraînement. Comme tout spectacle enregistré, elle s'ouvre verrouillée.
    @MainActor
    static func openTrainingShow(with openDocument: OpenDocumentAction) async {
        do {
            guard let source = trainingShow, FileManager.default.fileExists(atPath: source.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let parent = FileManager.default.temporaryDirectory.appending(path: "Spectacle d'entraînement", directoryHint: .isDirectory)
            let copy = try TrainingShow.freshCopy(of: source, in: parent)
            try await openDocument(at: copy)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Impossible d'ouvrir le spectacle d'entraînement"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

/// Fenêtre « Visite guidée » (menu Aide, et fenêtre d'accueil) : la page web, une copie de Lalabob sur laquelle
/// on agit. « Essayer maintenant », à la fin, ferme la visite et ouvre le spectacle d'entraînement.
struct TourView: View {
    @Environment(\.openDocument) private var openDocument

    var body: some View {
        Group {
            if let page = Tour.page {
                TourWebView(page: page) {
                    Task { await Tour.openTrainingShow(with: openDocument) }
                }
            } else {
                ContentUnavailableView(
                    "Visite introuvable", systemImage: "questionmark.circle",
                    description: Text("La visite guidée n'est pas dans cette version de Lalabob."))
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .background(Surface.window)
        .preferredColorScheme(.dark)
    }
}

private struct TourWebView: NSViewRepresentable {
    let page: URL
    let onTry: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTry: onTry) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "tour")
        // « Suivant » fait le geste à votre place (un curseur, sans clic réel) : les sons doivent pouvoir partir.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = TourKeyWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.appearance = NSAppearance(named: .darkAqua)
        view.underPageBackgroundColor = NSColor(srgbRed: 0x0B / 255, green: 0x0C / 255, blue: 0x0F / 255, alpha: 1)
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        return view
    }

    // Chargée une fois pour toutes : recharger la page effacerait la progression dans la visite.
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onTry = onTry
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "tour")
    }

    /// Reçoit « essayer » de la page (bouton « Essayer maintenant ») ; les liens web s'ouvrent dans le navigateur.
    /// Retenu par le `WKUserContentController` : retiré dans `dismantleNSView`.
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onTry: () -> Void

        init(onTry: @escaping () -> Void) { self.onTry = onTry }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.body as? String == "essayer" else { return }
            // La fenêtre de la visite se ferme, puis le spectacle d'entraînement s'ouvre.
            message.webView?.window?.close()
            onTry()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async
            -> WKNavigationActionPolicy
        {
            guard let url = navigationAction.request.url else { return .cancel }
            if url.isFileURL { return .allow }
            if url.scheme == "http" || url.scheme == "https" { NSWorkspace.shared.open(url) }
            return .cancel
        }
    }
}

/// ⌘L agit sur le cadenas de la copie, dans la page : il ne doit pas atteindre le menu de l'app, qui
/// verrouillerait un vrai spectacle.
private final class TourKeyWebView: WKWebView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "l" {
            evaluateJavaScript("window.lalabobVisite && window.lalabobVisite.act('lock')")
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
