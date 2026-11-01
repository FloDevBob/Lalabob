import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Barre d'en-tête : bibliothèque, logo, onglets de grilles, contrôleur, sortie audio, mode, Tout arrêter.
struct HeaderView: View {
    @Environment(ShowController.self) private var controller
    @Environment(PreviewController.self) private var preview
    @Environment(\.documentConfiguration) private var documentConfiguration
    @Binding var showsLibrary: Bool
    @Environment(\.midiSession) private var midiSession
    @State private var showsCalibration = false
    @State private var audioUsage = AudioFolderUsage.empty

    /// Nom du fichier du spectacle (sans « .lalabob »), ou « Nouveau spectacle » tant qu'il n'est pas enregistré.
    private var showName: String {
        documentConfiguration?.fileURL?.deletingPathExtension().lastPathComponent ?? controller.show.name
    }

    var body: some View {
        HStack(spacing: 12) {
            // À gauche : bibliothèque, logo, nom du spectacle, onglets de grilles (les onglets prennent la place restante).
            // Verrouillé : pas de bibliothèque, donc pas de bouton (et pas de trou à sa place avant le logo).
            if !controller.isLocked {
                Button(showsLibrary ? "Masquer la bibliothèque" : "Afficher la bibliothèque", icon: .sidebar) {
                    showsLibrary.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(HelpText.library(shown: showsLibrary))
            }

            Text("lalabob")
                .font(Typography.logo)
                .foregroundStyle(Surface.textPrimary)
            Text(showName)
                .font(.system(size: 12))
                .foregroundStyle(Surface.textTertiary)
                .lineLimit(1)
                .help("Nom du fichier du spectacle\n\(audioUsage.summary)")
                .task(id: controller.show.usedAudioFileNames) { await refreshAudioUsage() }

            GridTabsView()
                .frame(maxWidth: .infinity, alignment: .leading)

            // À droite : contrôleur, sortie audio, cadenas, Tout arrêter.
            controllerStatusControl
            outputPicker
            PairingButton()
            LockButton()
            Button("Tout arrêter", icon: .stop) {
                controller.stopAll()
                preview.stop()
            }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .help("Arrêter tous les sons (Échap)")
        }
        .padding(.leading, 88)  // boutons de fenêtre (rouge, jaune, vert : titre masqué) : ils finissent vers 70 pt, plus une marge de 18 pt
        .padding(.trailing, 20)
        .frame(height: 56)
        .background(Surface.chrome)
    }

    /// Mesure le dossier de sons hors du fil principal (l'infobulle du nom du spectacle).
    private func refreshAudioUsage() async {
        guard let directory = controller.audioDirectory else { return }
        let used = controller.show.usedAudioFileNames
        audioUsage = await Task.detached { AudioFolderUsage.measure(directory: directory, used: used) }.value
    }

    /// Le contrôleur connecté ; avec des LED RVB (Launchpad), un clic ouvre l'étalonnage des couleurs.
    @ViewBuilder
    private var controllerStatusControl: some View {
        if let session = midiSession, controller.connectedController?.hasRGBLEDs == true {
            Button { showsCalibration.toggle() } label: { controllerStatus }
                .buttonStyle(.plain)
                .hoverHighlight()
                .interactiveCursor(.link)
                .popover(isPresented: $showsCalibration, arrowEdge: .bottom) { LEDCalibrationView(session: session) }
                .help("Régler les couleurs des LED du Launchpad")
        } else {
            controllerStatus
        }
    }

    private var controllerStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(controller.connectedControllerName == nil ? Surface.textTertiary : Color.green)
                .frame(width: 8, height: 8)
            Text(controller.connectedControllerName ?? "Aucun contrôleur")
                .font(.system(size: 12))
                .foregroundStyle(Surface.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(controller.connectedControllerName.map { "\($0), connecté" } ?? "Aucun contrôleur connecté")
        .help(controller.connectedControllerName.map { "\($0) : contrôleur connecté" } ?? "Aucun Launchpad ni APC mini mk2 détecté : branchez-en un, il sera reconnu tout seul")
    }

    private var outputPicker: some View {
        Picker(
            "Sortie audio",
            selection: Binding(get: { controller.selectedOutputUID }, set: { controller.selectOutput(uid: $0) })
        ) {
            Text("Sortie par défaut").tag(String?.none)
            ForEach(controller.outputDevices) { device in
                Text(device.name).tag(String?.some(device.uid))
            }
            // Sortie mémorisée mais pas (encore) branchée : elle doit garder une entrée dans la liste.
            if let uid = controller.selectedOutputUID, !controller.outputDevices.contains(where: { $0.uid == uid }) {
                Text("Sortie débranchée").tag(String?.some(uid))
            }
        }
        .labelsHidden()
        .frame(width: 180)
        .help("Sortie audio du spectacle et de la pré-écoute")
    }
}

/// Bouton « Appairage » : entre dans le mode qui rattache les cases lumière aux cues de LightKey (déverrouillé seulement).
struct PairingButton: View {
    @Environment(ShowController.self) private var controller

    var body: some View {
        let active = controller.isPairingLights
        let locked = controller.isLocked
        Button {
            controller.setPairingLights(!active)
        } label: {
            IconLabel("Appairage", icon: .spotlight, size: 15)
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(active ? Surface.lightAccent : Surface.panel, in: .rect(cornerRadius: 8))
                .foregroundStyle(active ? Surface.window : Surface.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.45 : 1)
        .hoverHighlight()
        .interactiveCursor(.link, enabled: !locked)
        .help(locked ? "Déverrouillez pour appairer les cues lumière" : "Appairer les cases lumière aux cues de LightKey")
        .accessibilityLabel(active ? "Quitter l'appairage lumière" : "Appairage lumière")
    }
}

/// Cadenas : fermé, le spectacle se joue mais ne se modifie pas (⌘L).
struct LockButton: View {
    @Environment(ShowController.self) private var controller

    var body: some View {
        let locked = controller.isLocked
        Button {
            controller.isLocked.toggle()
        } label: {
            IconLabel(locked ? "Verrouillé" : "Déverrouillé", icon: locked ? .lock : .lockOpen, size: 15)
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(locked ? Surface.panel : Surface.lightAccent.opacity(0.18), in: .rect(cornerRadius: 8))
                .foregroundStyle(locked ? Surface.textSecondary : Surface.lightAccent)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .interactiveCursor(.link)
        .help(HelpText.lock(locked: locked))
        .accessibilityLabel(locked ? "Spectacle verrouillé" : "Spectacle déverrouillé")
        .accessibilityHint(locked ? "Déverrouille pour modifier" : "Verrouille pour jouer")
    }
}

/// Onglets de grilles : pastille numérotée, nom, nombre de pads. Double-clic pour renommer,
/// glisser pour réordonner, menu contextuel pour le reste ; ⌘1…⌘9 dans le menu Grilles.
struct GridTabsView: View {
    @Environment(ShowController.self) private var controller
    @State private var renaming: PadGrid.ID?
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(controller.show.grids.enumerated()), id: \.element.id) { index, grid in
                        tab(index: index, grid: grid)
                    }
                    if !controller.isLocked {
                        Button("Nouvelle grille", icon: .plus) { controller.addGrid() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Nouvelle grille (⌘T)")
                    }
                }
                .padding(.horizontal, 4)
                // Les onglets restent collés à gauche, même peu nombreux (le défilement ne sert qu'au-delà de la place).
                .frame(minWidth: proxy.size.width, alignment: .leading)
            }
        }
        .frame(height: 36)
    }

    private func tab(index: Int, grid: PadGrid) -> some View {
        let isSelected = index == controller.selectedGridIndex
        return HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .frame(width: 18, height: 18)
                .background(isSelected ? Surface.textPrimary : Surface.well, in: .circle)
                .foregroundStyle(isSelected ? Surface.window : Surface.textSecondary)
            if renaming == grid.id {
                TextField("Nom de la grille", text: $draftName)
                    .textFieldStyle(.plain)
                    .frame(width: 110)
                    .focused($nameFieldFocused)
                    .onSubmit { finishRenaming(index) }
                    .onChange(of: nameFieldFocused) { if !nameFieldFocused { finishRenaming(index) } }
            } else {
                Text(grid.name)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Surface.textPrimary : Surface.textSecondary)
                    .lineLimit(1)
            }
            Text("\(controller.padCount(inGrid: index))")
                .font(Typography.mono)
                .foregroundStyle(Surface.textTertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(isSelected ? Surface.panel : .clear, in: .rect(cornerRadius: 10))
        .contentShape(.rect(cornerRadius: 10))
        .hoverHighlight(cornerRadius: 10, enabled: !isSelected && renaming != grid.id)
        .interactiveCursor(.link, enabled: renaming != grid.id)
        .help(controller.isLocked ? "Grille \(index + 1) : \(grid.name)" : "Grille \(index + 1) : \(grid.name) · Double-cliquer pour renommer, glisser pour réordonner (⌘\(index + 1))")
        .onTapGesture(count: 2) {
            if controller.isLocked { controller.notifyLocked() } else { startRenaming(grid) }
        }
        .onTapGesture { controller.selectGrid(at: index) }
        .draggable(GridTabsView.dragToken(for: grid))
        .dropDestination(for: String.self) { items, _ in
            guard !controller.isLocked else {
                controller.notifyLocked()
                return false
            }
            guard let token = items.first, let source = sourceIndex(of: token) else { return false }
            controller.moveGrid(from: source, to: index)
            return true
        }
        .contextMenu {
            if controller.isLocked {
                Text("Spectacle verrouillé")
            } else {
                tabMenu(index: index, grid: grid)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("Grille \(index + 1), \(grid.name), \(controller.padCount(inGrid: index)) pads")
    }

    @ViewBuilder
    private func tabMenu(index: Int, grid: PadGrid) -> some View {
            Button("Renommer") { startRenaming(grid) }
            Button("Déplacer vers la gauche") { controller.moveGrid(from: index, to: index - 1) }
                .disabled(index == 0)
            Button("Déplacer vers la droite") { controller.moveGrid(from: index, to: index + 1) }
                .disabled(index == controller.show.grids.count - 1)
            Divider()
            Button("Supprimer la grille", role: .destructive) { controller.removeGrid(at: index) }
                .disabled(controller.show.grids.count == 1)
    }

    private static let dragPrefix = "lalabob-grid:"

    private static func dragToken(for grid: PadGrid) -> String { dragPrefix + grid.id.uuidString }

    private func sourceIndex(of token: String) -> Int? {
        guard token.hasPrefix(Self.dragPrefix), let id = UUID(uuidString: String(token.dropFirst(Self.dragPrefix.count)))
        else { return nil }
        return controller.show.grids.firstIndex { $0.id == id }
    }

    private func startRenaming(_ grid: PadGrid) {
        draftName = grid.name
        renaming = grid.id
        nameFieldFocused = true
    }

    private func finishRenaming(_ index: Int) {
        guard renaming != nil else { return }
        controller.renameGrid(at: index, to: draftName)
        renaming = nil
    }
}
