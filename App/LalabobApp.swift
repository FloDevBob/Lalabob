import AppKit
import LalabobDesign
import LalabobEngine
import SwiftUI

/// Fermeture de l'app : avant de quitter, les contrôleurs sont éteints et remis dans leur mode d'origine
/// (`ControllerSession.shutdown`) et la barre DMX suit le réglage « En quittant Lalabob » (`DMXSession.shutdown`), en même
/// temps. Ne coupe aucun son : la fermeture de l'app le fait déjà.
@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    /// La session MIDI de l'app (renseignée au lancement de la première fenêtre).
    static var session: ControllerSession?
    /// La lumière DMX de l'app.
    static var dmx: DMXSession?

    func applicationShouldTerminate(_ application: NSApplication) -> NSApplication.TerminateReply {
        guard Self.session != nil || Self.dmx != nil else { return .terminateNow }
        let session = Self.session, dmx = Self.dmx
        // Répond une seule fois, même si l'extinction traîne : au bout de 1,5 s on quitte quand même.
        var replied = false
        func reply() {
            guard !replied else { return }
            replied = true
            application.reply(toApplicationShouldTerminate: true)
        }
        Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                if let session { group.addTask { await session.shutdown() } }
                if let dmx { group.addTask { await dmx.shutdown() } }
            }
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
    /// La bibliothèque d'Apple Music (panneau des grilles Apple Music), partagée par toutes les fenêtres.
    @State private var musicLibrary = MusicLibraryController(library: AppleMusicLibrary())
    /// Le lecteur des pads Apple Music : Music n'a qu'un lecteur, partagé par toutes les fenêtres.
    @State private var musicPlayer = MusicPlaybackCoordinator(player: AppleMusicPlayer())
    /// Une seule session MIDI pour l'app, rattachée à la fenêtre active.
    @State private var midiSession = ControllerSession.live()
    /// Banc d'essai DMX : la sortie ne tourne que fenêtre ouverte.
    @State private var dmxBench = DMXTestBench()
    /// La lumière DMX (mode Projecteurs) : une barre, une console, rattachée à la fenêtre active.
    @State private var dmxSession = DMXSession()

    init() {
        Fonts.register()  // Fredoka, pour le logo
    }

    var body: some Scene {
        DocumentGroup(newDocument: { LalabobDocument() }) { file in
            DocumentWindow(document: file.document)
                .environment(library)
                .environment(preview)
                .environment(musicLibrary)
                .environment(musicPlayer)
                .environment(\.midiSession, midiSession)
                .environment(dmxSession)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1320, minHeight: 720)  // bibliothèque (273) + 8 colonnes de même largeur tiennent sans être coupées
                .modifier(FirstLaunchTour())
                .onAppear {
                    AppLifecycle.session = midiSession
                    AppLifecycle.dmx = dmxSession
                    // Le banc d'essai DMX prend le boîtier tant qu'il est ouvert ; le spectacle le reprend ensuite.
                    dmxBench.willOpen = { [dmxSession] in dmxSession.suspendForBench() }
                    dmxBench.didClose = { [dmxSession] in dmxSession.resumeAfterBench() }
                    midiSession?.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands { LalabobCommands() }

        Window("Aide de Lalabob", id: LalabobCommands.helpWindowID) {
            HelpView()
        }
        .defaultSize(width: 900, height: 640)

        Window("Visite guidée", id: Tour.windowID) {
            TourView()
        }
        .defaultSize(width: 1360, height: 820)

        Window("Banc d'essai lumière", id: LalabobCommands.benchWindowID) {
            LightingBenchView(session: midiSession)
        }

        Window("Banc d'essai DMX", id: LalabobCommands.dmxBenchWindowID) {
            DMXBenchView(bench: dmxBench)
        }
        .defaultSize(width: 620, height: 720)
    }
}
