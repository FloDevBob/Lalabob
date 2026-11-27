import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Fenêtre principale : en-tête, bibliothèque à gauche, grille au centre, inspecteur en bas.
/// Verrouillé (cadenas), la bibliothèque et l'inspecteur disparaissent : il ne reste que le jeu.
struct ContentView: View {
    @Environment(ShowController.self) private var controller
    @Environment(MusicLibraryController.self) private var musicLibrary: MusicLibraryController?
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsLibrary = true
    @State private var showsSettings = false
    /// Confirmation d'un changement de type qui retire quelque chose (colonne ou pad).
    @State private var prompter = ConversionPrompter()

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
        .environment(prompter)
        // Titre masqué : sans cela, une bande vide (la barre de titre invisible) reste en haut de la fenêtre. L'en-tête
        // remonte jusqu'au bord et les boutons de fenêtre se posent sur sa partie gauche, laissée libre.
        .ignoresSafeArea(.container, edges: .top)
        .background(Surface.window)
        .overlay(alignment: .top) { lockBanner }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: controller.lockNotice)
        .focusedSceneValue(\.showController, controller)
        .focusedSceneValue(\.showSettingsPresented, $showsSettings)
        .sheet(isPresented: $showsSettings) { ShowSettingsView().environment(controller) }
        .sheet(item: Binding(get: { prompter.pending }, set: { prompter.pending = $0 })) { pending in
            ConversionSheet(pending: pending, close: { prompter.pending = nil })
        }
        .alert(
            "Changement impossible",
            isPresented: Binding(get: { controller.conversionNotice != nil }, set: { if !$0 { controller.dismissConversionNotice() } })
        ) {
            Button("OK") { controller.dismissConversionNotice() }
        } message: {
            Text(controller.conversionNotice ?? "")
        }
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
        .task(id: musicTrackIDs) {
            // Grille Apple Music : quels morceaux des pads sont dans le nuage ou introuvables (☁, « Introuvable »).
            guard !musicTrackIDs.isEmpty else { return }
            await musicLibrary?.refreshAvailability(of: musicTrackIDs)
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
                        Group {
                            if controller.currentGrid.kind == .appleMusic { MusicLibraryView() } else { LibraryView() }
                        }
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
    /// Les morceaux des pads de la grille affichée (grille Apple Music).
    private var musicTrackIDs: Set<String> {
        Set(controller.currentGrid.columns.flatMap { $0.slots.compactMap { $0?.music?.persistentID } })
    }

    fileprivate var libraryIsVisible: Bool { showsLibrary && !controller.isLocked }

    /// Verrouillé, le panneau ne s'affiche que pour un son (les cases vides et les cues n'ont rien à y piloter).
    fileprivate func showsInspector(for position: GridPosition) -> Bool {
        guard controller.isLocked else { return true }
        guard let pad = controller.pad(at: position), pad.audio != nil || pad.music != nil else { return false }
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

#Preview("Colonnes égales : une colonne lumière en position 3") {
    Fonts.register()
    var grid = PadGrid.empty(name: "Essai")
    grid.columns[2] = Column.empty(name: "Éclairage", kind: .light)
    grid.columns[6] = Column.empty(name: "Sons", kind: .audio)
    grid[GridPosition(column: 2, row: 0)] = Pad(
        title: "Plein feu", subtitle: "Cue", tint: .ambre,
        light: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0)))
    grid[GridPosition(column: 6, row: 0)] = Pad(
        title: "Rire", subtitle: "Public", tint: .vert, audio: AudioClip(fileName: "rire.wav"))
    return ContentView()
        .environment(ShowController(show: Show(name: "Essai", grids: [grid])))
        .environment(LibraryController(securityScoped: false))
        .environment(PreviewController())
        .frame(width: 1320, height: 780)
        .preferredColorScheme(.dark)
}

#Preview("Colonne son et lumière : types et états des pads") {
    Fonts.register()
    var grid = PadGrid.empty(name: "Essai")
    grid.columns[0] = Column.empty(name: "Scènes", kind: .mixed)
    grid.columns[1] = Column.empty(name: "Sons", kind: .audio)
    let cue = LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0), isPaired: true)
    let sound = AudioClip(fileName: "essai.wav")
    // Colonne mixte : son seul, cue seule, son et lumière, « en attente de son », puis deux cases vides (« Son » / « Cue »).
    grid[GridPosition(column: 0, row: 0)] = Pad(title: "Pluie", subtitle: "Son seul", tint: .ciel, audio: sound)
    grid[GridPosition(column: 0, row: 1)] = Pad(title: "Face", subtitle: "Cue seule", tint: .blanc, light: cue)
    grid[GridPosition(column: 0, row: 2)] = Pad(title: "Aube", subtitle: "Son et lumière", tint: .ambre, audio: sound, light: cue)
    grid[GridPosition(column: 0, row: 3)] = Pad(title: "Orage", subtitle: "Son et lumière", tint: .azur, audio: sound, light: .blank)
    grid[GridPosition(column: 0, row: 4)] = Pad(title: "À venir", subtitle: "En attente de son", tint: .rose, light: cue, awaitsSound: true)
    grid[GridPosition(column: 1, row: 0)] = Pad(title: "Rire", subtitle: "Public", tint: .vert, audio: sound)
    let controller = ShowController(show: Show(name: "Essai", grids: [grid]))
    controller.selection = GridPosition(column: 0, row: 2)
    return ContentView()
        .environment(controller)
        .environment(LibraryController(securityScoped: false))
        .environment(PreviewController())
        .frame(width: 1320, height: 780)
        .preferredColorScheme(.dark)
}

#Preview("Plein écran portable (1440 × 900), pad sélectionné") {
    Fonts.register()
    var grid = PadGrid.empty(name: "Essai")
    let position = GridPosition(column: 1, row: 2)
    grid[position] = Pad(
        title: "Orage lointain", subtitle: "Ambiance", tint: .azur,
        audio: AudioClip(fileName: "essai.wav"))
    grid[GridPosition(column: 0, row: 0)] = Pad(
        title: "Rire", subtitle: "Public", tint: .ambre, audio: AudioClip(fileName: "rire.wav"))
    for (index, title) in ["Plein feu", "Noir", "Ambiance"].enumerated() {
        grid[GridPosition(column: 6, row: index)] = Pad(
            title: title, subtitle: "Cue", tint: [.orange, .azur, .rose][index],
            light: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0)))
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
