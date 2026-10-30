import LalabobEngine
import SwiftUI

@main
struct LalabobApp: App {
    @State private var library = LibraryController()
    /// Une seule session MIDI pour l'app, rattachée à la fenêtre active.
    @State private var midiSession = ControllerSession.live()

    var body: some Scene {
        DocumentGroup(newDocument: { LalabobDocument() }) { file in
            DocumentWindow(document: file.document)
                .environment(library)
                .environment(\.midiSession, midiSession)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 720)
                .onAppear { midiSession?.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands { LalabobCommands() }
    }
}
