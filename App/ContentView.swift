import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Fenêtre principale : en-tête, bibliothèque à gauche, grille au centre, inspecteur en bas.
/// Verrouillé (cadenas), la bibliothèque et l'inspecteur disparaissent : il ne reste que le jeu.
struct ContentView: View {
    @Environment(ShowController.self) private var controller
    @Environment(\.undoManager) private var undoManager
    @State private var showsLibrary = true

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(showsLibrary: $showsLibrary)
            Divider().overlay(Color.white.opacity(0.06))
            HStack(spacing: 0) {
                if showsLibrary && !controller.isLocked {
                    LibraryView()
                        .frame(width: 272)
                    Divider().overlay(Color.white.opacity(0.06))
                }
                VStack(spacing: 0) {
                    ScrollView {
                        GridView()
                            .padding(20)
                    }
                    if !controller.isLocked, let selection = controller.selection {
                        Divider().overlay(Color.white.opacity(0.06))
                        InspectorView(position: selection)
                    }
                }
            }
        }
        .background(Surface.window)
        .overlay(alignment: .top) { lockBanner }
        .focusedSceneValue(\.showController, controller)
        .alert(
            "Import impossible",
            isPresented: Binding(get: { controller.importError != nil }, set: { if !$0 { controller.dismissImportError() } })
        ) {
            Button("OK") { controller.dismissImportError() }
        } message: {
            Text(controller.importError ?? "")
        }
        .task(id: controller.lockNotice) {
            guard controller.lockNotice != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            controller.dismissLockNotice()
        }
        .onAppear { controller.undoManager = undoManager }
        .onChange(of: undoManager.map(ObjectIdentifier.init)) { controller.undoManager = undoManager }
    }
}

extension ContentView {
    /// Bandeau affiché quand on tente de modifier un spectacle verrouillé.
    @ViewBuilder
    fileprivate var lockBanner: some View {
        if let notice = controller.lockNotice {
            HStack(spacing: 10) {
                Icon.lock.view(size: 15)
                Text(notice)
                    .font(.system(size: 12.5, weight: .medium))
                Button("Déverrouiller") { controller.isLocked = false }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Surface.panel, in: .capsule)
            .overlay(Capsule().stroke(Color.white.opacity(0.12)))
            .foregroundStyle(Surface.textPrimary)
            .padding(.top, 64)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityAddTraits(.isStaticText)
        }
    }
}

#Preview {
    Fonts.register()
    return ContentView()
        .environment(ShowController())
        .environment(LibraryController(securityScoped: false))
        .frame(width: 1400, height: 900)
        .preferredColorScheme(.dark)
}
