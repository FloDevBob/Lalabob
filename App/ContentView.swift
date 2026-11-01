import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Fenêtre principale : en-tête, bibliothèque à gauche, grille au centre, inspecteur en bas.
/// Verrouillé (cadenas), la bibliothèque et l'inspecteur disparaissent : il ne reste que le jeu.
struct ContentView: View {
    @Environment(ShowController.self) private var controller
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsLibrary = true

    /// En-tête de la fenêtre (56) et son filet.
    private static let headerAreaHeight: CGFloat = 57
    /// Barre du bas (196) et son filet : toujours réservée, même sans pad sélectionné, pour que la grille ne se
    /// redimensionne pas quand un son démarre ou qu'on sélectionne un pad.
    private static let inspectorAreaHeight: CGFloat = Metrics.inspectorHeight + 1

    var body: some View {
        GeometryReader { proxy in
            content
                .environment(
                    \.gridDensity,
                    GridDensity.fitting(
                        availableHeight: proxy.size.height - Self.headerAreaHeight - Self.inspectorAreaHeight))
        }
        // Titre masqué : sans cela, une bande vide (la barre de titre invisible) reste en haut de la fenêtre. L'en-tête
        // remonte jusqu'au bord et les boutons de fenêtre se posent sur sa partie gauche, laissée libre.
        .ignoresSafeArea(.container, edges: .top)
        .background(Surface.window)
        .overlay(alignment: .top) { lockBanner }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: controller.lockNotice)
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

    private var content: some View {
        VStack(spacing: 0) {
            HeaderView(showsLibrary: $showsLibrary)
            Divider().overlay(Color.white.opacity(0.06))
            HStack(spacing: 0) {
                if libraryIsVisible {
                    // Un seul bloc (bibliothèque + filet) : il glisse depuis la gauche en entrant et en sortant.
                    HStack(spacing: 0) {
                        LibraryView()
                            .frame(width: 272)
                        Divider().overlay(Color.white.opacity(0.06))
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                VStack(spacing: 0) {
                    ScrollView {
                        GridView()
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                    // Déverrouillé : le pad sélectionné. Verrouillé : le son lancé (version en lecture seule).
                    // La barre est toujours là : sans rien à régler, c'est l'écran de repos (`IdleBar`).
                    VStack(spacing: 0) {
                        Divider().overlay(Color.white.opacity(0.06))
                        if controller.isPairingLights, !controller.isLocked {
                            PairingBar()
                        } else if controller.selectedPositions.count > 1, !controller.isLocked {
                            MultiSelectionBar()
                        } else if let selection = controller.selection, showsInspector(for: selection) {
                            InspectorView(position: selection)
                        } else {
                            // Rien à régler : l'écran de repos garde la place (et la grille ne bouge pas).
                            IdleBar(emptyPosition: nil)
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : Motion.panel, value: libraryIsVisible)
        }
    }
}

extension ContentView {
    /// La bibliothèque est ouverte (et le spectacle déverrouillé : verrouillé, il n'y a pas de bibliothèque).
    fileprivate var libraryIsVisible: Bool { showsLibrary && !controller.isLocked }

    /// Verrouillé, le panneau ne s'affiche que pour un son (les cases vides et les cues n'ont rien à y piloter).
    fileprivate func showsInspector(for position: GridPosition) -> Bool {
        guard controller.isLocked else { return true }
        guard let pad = controller.pad(at: position), case .audio = pad.content else { return false }
        return true
    }

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
                    .help("Ouvrir le cadenas pour pouvoir modifier (⌘L)")
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
        .environment(PreviewController())
        .frame(width: 1400, height: 900)
        .preferredColorScheme(.dark)
}

#Preview("Plein écran portable (1440 × 900), pad sélectionné") {
    Fonts.register()
    var grid = PadGrid.empty(name: "Essai")
    let position = GridPosition(column: 1, row: 2)
    grid[position] = Pad(
        title: "Orage lointain", subtitle: "Ambiance", tint: .azur,
        content: .audio(clip: AudioClip(fileName: "essai.wav")))
    grid[GridPosition(column: 0, row: 0)] = Pad(
        title: "Rire", subtitle: "Public", tint: .ambre, content: .audio(clip: AudioClip(fileName: "rire.wav")))
    for (index, title) in ["Plein feu", "Noir", "Ambiance"].enumerated() {
        grid[GridPosition(column: 6, row: index)] = Pad(
            title: title, subtitle: "Cue", tint: [.orange, .azur, .rose][index],
            content: .light(cue: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0))))
    }
    let controller = ShowController(show: Show(name: "Essai", grids: [grid]))
    controller.selection = position
    return ContentView()
        .environment(controller)
        .environment(LibraryController(securityScoped: false))
        .environment(PreviewController())
        .frame(width: 1440, height: 900)
        .preferredColorScheme(.dark)
}
