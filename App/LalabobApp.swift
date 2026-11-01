import LalabobDesign
import LalabobEngine
import SwiftUI

@main
struct LalabobApp: App {
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
                .onAppear { midiSession?.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands { LalabobCommands() }

        Window("Banc d'essai lumière", id: LalabobCommands.benchWindowID) {
            LightingBenchView(session: midiSession)
        }
    }
}
