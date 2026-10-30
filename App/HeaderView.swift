import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Barre d'en-tête : bibliothèque, logo, onglets de grilles, contrôleur, sortie audio, mode, Tout arrêter.
struct HeaderView: View {
    @Environment(ShowController.self) private var controller
    @Environment(\.documentConfiguration) private var documentConfiguration
    @Binding var showsLibrary: Bool

    /// Nom du fichier du spectacle (sans « .lalabob »), ou « Nouveau spectacle » tant qu'il n'est pas enregistré.
    private var showName: String {
        documentConfiguration?.fileURL?.deletingPathExtension().lastPathComponent ?? controller.show.name
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(showsLibrary ? "Masquer la bibliothèque" : "Afficher la bibliothèque", systemImage: "sidebar.left") {
                showsLibrary.toggle()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            Text("Lalabob")
                .font(Typography.logo)
                .foregroundStyle(Surface.textPrimary)
            Text(showName)
                .font(.system(size: 12))
                .foregroundStyle(Surface.textTertiary)
                .lineLimit(1)

            GridTabsView()
                .frame(maxWidth: .infinity)

            controllerStatus
            outputPicker
            modePicker
            Button("Tout arrêter", systemImage: "stop.fill") { controller.stopAll() }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(.leading, 80)  // laisse la place aux boutons de fenêtre
        .padding(.trailing, 20)
        .frame(height: 56)
        .background(Surface.chrome)
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
        }
        .labelsHidden()
        .frame(width: 180)
        .help("Sortie audio")
    }

    private var modePicker: some View {
        Picker("Mode", selection: Bindable(controller).mode) {
            Text("Édition").tag(InteractionMode.edit)
            Text("Live").tag(InteractionMode.live)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 140)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(controller.show.grids.enumerated()), id: \.element.id) { index, grid in
                    tab(index: index, grid: grid)
                }
                Button("Nouvelle grille", systemImage: "plus") { controller.addGrid() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Nouvelle grille (⌘T)")
            }
            .padding(.horizontal, 4)
        }
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
        .onTapGesture(count: 2) { startRenaming(grid) }
        .onTapGesture { controller.selectGrid(at: index) }
        .draggable(GridTabsView.dragToken(for: grid))
        .dropDestination(for: String.self) { items, _ in
            guard let token = items.first, let source = sourceIndex(of: token) else { return false }
            controller.moveGrid(from: source, to: index)
            return true
        }
        .contextMenu {
            Button("Renommer") { startRenaming(grid) }
            Button("Déplacer vers la gauche") { controller.moveGrid(from: index, to: index - 1) }
                .disabled(index == 0)
            Button("Déplacer vers la droite") { controller.moveGrid(from: index, to: index + 1) }
                .disabled(index == controller.show.grids.count - 1)
            Divider()
            Button("Supprimer la grille", role: .destructive) { controller.removeGrid(at: index) }
                .disabled(controller.show.grids.count == 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("Grille \(index + 1), \(grid.name), \(controller.padCount(inGrid: index)) pads")
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
