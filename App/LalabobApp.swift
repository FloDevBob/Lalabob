import LalabobEngine
import SwiftUI

@main
struct LalabobApp: App {
    @State private var controller = ShowController.live(audioDirectory: LalabobApp.trialAudioDirectory)

    /// Avant le jalon 4 (documents `.lalabob`), les sons d'essai se déposent dans le dossier de l'app :
    /// ~/Library/Containers/fr.flodevbob.Lalabob/Data/Library/Application Support/Lalabob/Audio
    private static var trialAudioDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Lalabob/Audio", directoryHint: .isDirectory)
    }

    var body: some Scene {
        WindowGroup("Lalabob") {
            ContentView()
                .environment(controller)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 720)
                .task { await controller.observePlayback() }
                .task { await controller.observeOutputDevices() }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
