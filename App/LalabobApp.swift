import AppKit
import LalabobDesign
import LalabobEngine
import SwiftUI

/// Fermeture de l'app : avant de quitter, les contrôleurs sont éteints et remis dans leur mode d'origine
/// (`ControllerSession.shutdown`). Ne coupe aucun son : la fermeture de l'app le fait déjà.
@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    /// La session MIDI de l'app (renseignée au lancement de la première fenêtre).
    static var session: ControllerSession?

    func applicationShouldTerminate(_ application: NSApplication) -> NSApplication.TerminateReply {
        guard let session = Self.session else { return .terminateNow }
        // Répond une seule fois, même si l'extinction traîne : au bout de 1,5 s on quitte quand même.
        var replied = false
        func reply() {
            guard !replied else { return }
            replied = true
            application.reply(toApplicationShouldTerminate: true)
        }
        Task { @MainActor in
            await session.shutdown()
            reply()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            reply()
        }
        return .terminateLater
    }
}

@main
struct LalabobApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @State private var library = LibraryController()
    @State private var preview = PreviewController()
    /// Une seule session MIDI pour l'app, rattachée à la fenêtre active.
    @State private var midiSession = ControllerSession.live()

    init() {
        Fonts.register()  // Fredoka, pour le logo
    }

    var body: some Scene {
        DocumentGroup(newDocument: { LalabobDocument() }) { file in
            DocumentWindow(document: file.document)
                .environment(library)
                .environment(preview)
                .environment(\.midiSession, midiSession)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1320, minHeight: 720)  // bibliothèque (273) + 6 colonnes sons + zone lumière tiennent sans être coupées
                .onAppear {
                    AppLifecycle.session = midiSession
                    midiSession?.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands { LalabobCommands() }

        Window("Aide de Lalabob", id: LalabobCommands.helpWindowID) {
            HelpView()
        }
        .defaultSize(width: 900, height: 640)

        Window("Banc d'essai lumière", id: LalabobCommands.benchWindowID) {
            LightingBenchView(session: midiSession)
        }
    }
}
