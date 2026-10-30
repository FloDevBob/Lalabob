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
                .frame(minWidth: 1100, minHeight: 720)
                .onAppear { midiSession?.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands { LalabobCommands() }
    }
}
