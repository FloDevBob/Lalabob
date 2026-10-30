import LalabobEngine
import SwiftUI

@main
struct LalabobApp: App {
    @State private var controller = ShowController()

    var body: some Scene {
        WindowGroup("Lalabob") {
            ContentView()
                .environment(controller)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
