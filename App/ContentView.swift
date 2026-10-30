import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Fenêtre principale : en-tête, bibliothèque à gauche, grille au centre, inspecteur en bas (mode Édition).
struct ContentView: View {
    @Environment(ShowController.self) private var controller
    @Environment(\.undoManager) private var undoManager
    @State private var showsLibrary = true

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(showsLibrary: $showsLibrary)
            Divider().overlay(Color.white.opacity(0.06))
            HStack(spacing: 0) {
                if showsLibrary {
                    LibraryView()
                        .frame(width: 272)
                    Divider().overlay(Color.white.opacity(0.06))
                }
                VStack(spacing: 0) {
                    ScrollView {
                        GridView()
                            .padding(20)
                    }
                    if controller.mode == .edit, let selection = controller.selection {
                        Divider().overlay(Color.white.opacity(0.06))
                        InspectorView(position: selection)
                    }
                }
            }
        }
        .background(Surface.window)
        .focusedSceneValue(\.showController, controller)
        .onAppear { controller.undoManager = undoManager }
        .onChange(of: undoManager.map(ObjectIdentifier.init)) { controller.undoManager = undoManager }
    }
}

#Preview {
    ContentView()
        .environment(ShowController())
        .environment(LibraryController(securityScoped: false))
        .frame(width: 1400, height: 900)
        .preferredColorScheme(.dark)
}
