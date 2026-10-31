import AppKit
import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI
import UniformTypeIdentifiers
import os

/// La grille : 6 colonnes sons, puis 2 colonnes lumière dans une zone ambrée.
/// Elle reçoit ⌘X / ⌘C / ⌘V / ⌫ quand elle a le focus (un clic sur un pad le lui donne) ;
/// verrouillée, ces commandes sont refusées par `ShowController` avec un message.
struct GridView: View {
    @Environment(ShowController.self) private var controller
    @FocusState private var focused: Bool

    var body: some View {
        let grid = controller.currentGrid
        HStack(alignment: .top, spacing: 16) {
            HStack(spacing: Metrics.columnSpacing) {
                ForEach(indices(of: .audio, in: grid), id: \.self) { index in
                    ColumnView(index: index, onPress: { focused = true })
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: Metrics.columnSpacing) {
                ForEach(indices(of: .light, in: grid), id: \.self) { index in
                    ColumnView(index: index, onPress: { focused = true })
                }
            }
            // Marge horizontale seulement : les en-têtes et les pads des colonnes lumière doivent tomber à la même
            // hauteur que ceux des colonnes sons (le cadre ambré déborde, lui, de 8 px en haut et en bas).
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .background {
                RoundedRectangle(cornerRadius: Metrics.panelCornerRadius)
                    .fill(Surface.lightZone)
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.panelCornerRadius)
                            .stroke(Surface.lightAccent.opacity(0.12))
                    )
                    .padding(.vertical, -8)
            }
            .frame(width: 280)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onCopyCommand {
            controller.copySelection()
            return [NSItemProvider(object: PadDragToken.clipboardMarker as NSString)]
        }
        .onCutCommand {
            controller.cutSelection()
            return [NSItemProvider(object: PadDragToken.clipboardMarker as NSString)]
        }
        .onPasteCommand(of: [.plainText]) { _ in controller.pasteAtSelection() }
        .onDeleteCommand { controller.clearSelection() }
    }

    private func indices(of kind: ColumnKind, in grid: PadGrid) -> [Int] {
        grid.columns.indices.filter { grid.columns[$0].kind == kind }
    }
}

struct ColumnView: View {
    /// « 75 % · CC 54 » : le niveau et le CC que reçoit LightKey (sans CC tant qu'aucun contrôleur n'est connu).
    private func lightValueText(_ column: Column) -> String {
        let percent = Int((column.level * 100).rounded())
        guard let cc = controller.lightFaderCC(forColumn: index) else { return "\(percent) %" }
        return "\(percent) % · CC \(cc)"
    }

    @Environment(ShowController.self) private var controller
    let index: Int
    let onPress: () -> Void

    var body: some View {
        let column = controller.currentGrid.columns[index]
        VStack(spacing: Metrics.padSpacing) {
            HStack(spacing: 8) {
                (column.kind == .audio ? Icon.music : Icon.spotlight).view(size: 16)
                    .foregroundStyle(column.kind == .audio ? Surface.textSecondary : Surface.lightAccent)
                ColumnTitle(index: index, name: column.name)
                Spacer(minLength: 0)
                Text("\(index + 1)")
                    .font(Typography.mono)
                    .foregroundStyle(Surface.textTertiary)
            }
            .frame(height: 30)

            ForEach(0..<PadGrid.size, id: \.self) { row in
                PadView(position: GridPosition(column: index, row: row), kind: column.kind, onPress: onPress)
            }

            // Carte sous la colonne : un son a fader, vumètre du signal réel et dB ; une cue lumière a un fader
            // (CC envoyé à LightKey, comme le fader de l'Akai), un soleil qui suit le niveau, la valeur en % et le CC.
            Group {
                if column.kind == .audio {
                    VerticalFader(
                        name: column.name,
                        level: Binding(get: { column.level }, set: { controller.setColumnLevel(index, level: $0) })
                    ) {
                        LevelMeter(column: index).frame(width: 14)
                    }
                } else {
                    VerticalFader(
                        name: column.name,
                        level: Binding(get: { column.level }, set: { controller.setLightFader(column: index, level: $0) }),
                        valueText: lightValueText(column),
                        defaultLevel: 1
                    ) {
                        Icon.sun.view(size: 16)
                            .foregroundStyle(Surface.lightAccent)
                            .opacity(0.25 + 0.75 * column.level)
                            .frame(width: 16, height: 120, alignment: .top)
                    }
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Surface.panel, in: .rect(cornerRadius: Metrics.padCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                    .stroke(column.kind == .light ? Surface.lightAccent.opacity(0.12) : Color.white.opacity(0.06))
            )
            .padding(.top, 4)
        }
        .frame(minWidth: 110, maxWidth: .infinity)
    }
}

/// Nom d'une colonne : double-clic pour le modifier (déverrouillé), Entrée valide, Échap annule, un clic ailleurs valide.
struct ColumnTitle: View {
    @Environment(ShowController.self) private var controller
    let index: Int
    let name: String

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let font = Font.system(size: 12.5, weight: .semibold)

    var body: some View {
        Group {
            if isEditing {
                TextField("Nom de la colonne", text: $draft)
                    .textFieldStyle(.plain)
                    .font(font)
                    .foregroundStyle(Surface.textPrimary)
                    .focused($focused)
                    .onSubmit { focused = false }
                    .onExitCommand {
                        isEditing = false
                        focused = false
                    }
                    .onChange(of: focused) { wasFocused, isFocused in
                        if wasFocused, !isFocused { commit() }
                    }
            } else {
                Text(name)
                    .font(font)
                    .foregroundStyle(Surface.textPrimary)
                    .lineLimit(1)
                    .help(controller.isLocked ? "" : "Double-cliquer pour renommer la colonne")
                    .onTapGesture(count: 2) { start() }
            }
        }
        // Un changement d'onglet ou le verrouillage pendant la saisie l'abandonne.
        .onChange(of: controller.isLocked) { isEditing = false }
        .onChange(of: controller.selectedGridIndex) { isEditing = false }
        .accessibilityLabel("Colonne \(index + 1) : \(name)")
        .accessibilityAction(named: "Renommer") { start() }
    }

    private func start() {
        guard !controller.isLocked else { return }
        draft = name
        isEditing = true
        DispatchQueue.main.async { focused = true }
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false
        controller.renameColumn(at: index, to: draft)
    }
}

/// Le glisser d'un pad n'existe que déverrouillé (sinon le clic doit jouer sans hésitation).
struct PadDragSource: ViewModifier {
    let enabled: Bool
    let provider: () -> NSItemProvider

    func body(content: Content) -> some View {
        if enabled {
            content.onDrag(provider)
        } else {
            content
        }
    }
}

/// Ce qu'on glisse d'un pad à l'autre : la grille et la case d'origine, en texte.
enum PadDragToken {
    private static let prefix = "lalabob-pad:"
    /// Mis dans le presse-papiers par ⌘C / ⌘X : le pad lui-même reste dans `ShowController`.
    static let clipboardMarker = "lalabob-pad-clipboard"

    static func string(grid: PadGrid.ID, position: GridPosition) -> String {
        "\(prefix)\(grid.uuidString):\(position.column):\(position.row)"
    }

    static func parse(_ text: String) -> (grid: PadGrid.ID, position: GridPosition)? {
        guard text.hasPrefix(prefix) else { return nil }
        let parts = text.dropFirst(prefix.count).split(separator: ":")
        guard parts.count == 3, let grid = UUID(uuidString: String(parts[0])), let column = Int(parts[1]),
            let row = Int(parts[2])
        else { return nil }
        let position = GridPosition(column: column, row: row)
        return position.isValid ? (grid, position) : nil
    }
}

/// Surbrillance d'une case pendant un glisser.
enum DropHighlight: Equatable {
    case move, copy
}

struct PadView: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let kind: ColumnKind
    let onPress: () -> Void
    @State private var dropHighlight: DropHighlight?

    var body: some View {
        let pad = controller.pad(at: position)
        let event = pad.flatMap { controller.playback[$0.id] }
        let isSelected = controller.selectedPositions.contains(position)

        // Pas de `Button` : sur macOS il capte la souris et empêche le glisser de démarrer.
        Group {
            if let pad {
                filled(pad, event: event)
            } else {
                empty
            }
        }
        .frame(height: Metrics.padHeight)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Metrics.padCornerRadius).stroke(.white, lineWidth: 2)
            }
        }
        .overlay { dropOverlay }
        .overlay { groupDropOverlay }
        .contentShape(.rect(cornerRadius: Metrics.padCornerRadius))
        // Verrouillé : un clic joue tout de suite. Déverrouillé : un clic sélectionne, un double-clic fait écouter.
        .onTapGesture(count: 2) { controller.audition(at: position) }
        .simultaneousGesture(TapGesture().onEnded(activate))
        .modifier(PadDragSource(enabled: pad != nil && !controller.isLocked) {
            let token = PadDragToken.string(grid: controller.currentGrid.id, position: position)
            controller.beginDrag(from: position)
            PadDropDelegate.log.info("Glisser : départ de \(position.description, privacy: .public)")
            return NSItemProvider(object: token as NSString)
        })
        .onDrop(
            of: [.fileURL, .plainText],
            delegate: PadDropDelegate(position: position, controller: controller, highlight: $dropHighlight)
        )
        .contextMenu { PadContextMenu(position: position) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pad.map { "\($0.title), \($0.subtitle)" } ?? (kind == .audio ? "Case vide" : "Case lumière vide"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { activate() }
    }

    /// Clic : ⇧ étend la sélection en rectangle depuis l'ancre, ⌘ ajoute ou retire la case, sinon la case seule.
    private func activate() {
        onPress()
        let modifiers = NSEvent.modifierFlags
        let mode: ShowController.SelectionMode =
            modifiers.contains(.shift) ? .range : modifiers.contains(.command) ? .toggle : .replace
        controller.press(at: position, mode: mode)
    }

    /// Glisser un groupe de pads : chaque case où il tomberait est teintée (blanc) ; en rouge si le dépôt serait refusé.
    @ViewBuilder
    private var groupDropOverlay: some View {
        if let preview = controller.dragPreview, preview.positions.contains(position) {
            let color: Color = preview.isAllowed ? .white : .red
            RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                .fill(color.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                        .strokeBorder(color.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                )
                .overlay(alignment: .topTrailing) {
                    if preview.isAllowed, preview.isCopy {
                        Text("Copie")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white, in: .capsule)
                            .foregroundStyle(Surface.window)
                            .padding(6)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if let dropHighlight {
            RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                .strokeBorder(.white, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .overlay(alignment: .topTrailing) {
                    if dropHighlight == .copy {
                        Text("Copie")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white, in: .capsule)
                            .foregroundStyle(Surface.window)
                            .padding(6)
                    }
                }
        }
    }

    private func filled(_ pad: Pad, event: PlaybackEvent?) -> some View {
        let vivid = pad.tint.vividColor
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(pad.title).font(Typography.padTitle).lineLimit(1)
                Spacer(minLength: 0)
                if case .paused = event?.state { Icon.pause.view(size: 12) }
                if case .playing = event?.state { MiniEqualizer(color: pad.tint.vividColor, isAnimating: true) }
            }
            Text(pad.subtitle).font(Typography.padSubtitle).opacity(0.88).lineLimit(1)
        }
        .foregroundStyle(pad.tint.labelColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .background(pad.tint.surfaceColor, in: .rect(cornerRadius: Metrics.padCornerRadius))
        .overlay(alignment: .bottom) { progressBar(event, color: vivid) }
        .overlay {
            if let event {
                RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                    .stroke(vivid.opacity(event.state.isPaused ? 0.45 : 1), lineWidth: 2)
            }
        }
        .shadow(color: event.map { $0.state.isPaused ? .clear : vivid.opacity(0.45) } ?? .clear, radius: 8)
    }

    /// Barre de progression de 3 px ; figée et estompée en pause. Une boucle revient au début.
    @ViewBuilder
    private func progressBar(_ event: PlaybackEvent?, color: Color) -> some View {
        if let event, event.duration > 0 {
            TimelineView(.animation(paused: event.state.isPaused)) { _ in
                GeometryReader { geometry in
                    let elapsed = event.state.elapsed(now: ProcessInfo.processInfo.systemUptime)
                    let fraction = min(max(elapsed.truncatingRemainder(dividingBy: event.duration) / event.duration, 0), 1)
                    Capsule()
                        .fill(color.opacity(event.state.isPaused ? 0.4 : 1))
                        .frame(width: geometry.size.width * fraction, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }

    private var empty: some View {
        // Verrouillé, l'invitation à déposer n'a pas de sens : la case reste, discrète, sans texte.
        // ZStack et non Group : un Group vide n'a aucune vue sur laquelle poser cadre et bordure, la case disparaîtrait.
        ZStack {
            if !controller.isLocked {
                IconLabel(kind == .audio ? "Déposer un son" : "Nouvelle cue", icon: .plus, size: 13)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Surface.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                    .strokeBorder(Surface.emptyPadStroke, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
    }
}

/// Dépôt sur une case : un fichier son (Finder ou bibliothèque) crée le pad ; un pad le déplace ou l'échange ;
/// avec ⌥, il le duplique.
struct PadDropDelegate: DropDelegate {
    nonisolated static let log = Logger(subsystem: "fr.lalabob.app", category: "drop")

    let position: GridPosition
    let controller: ShowController
    @Binding var highlight: DropHighlight?

    private var optionHeld: Bool { NSEvent.modifierFlags.contains(.option) }

    func validateDrop(info: DropInfo) -> Bool {
        guard !controller.isLocked else {
            controller.notifyLocked()
            return false
        }
        let valid = info.hasItemsConforming(to: [.fileURL, .plainText])
        Self.log.info("Glisser : validation sur \(position.description, privacy: .public) → \(valid)")
        return valid
    }

    func dropEntered(info: DropInfo) {
        Self.log.info("Glisser : entrée sur \(position.description, privacy: .public)")
        highlight = isPadDrag(info) && optionHeld ? .copy : .move
        updateGroupPreview(info)
    }

    /// Un groupe de pads qu'on glisse : toutes les cases d'arrivée sont montrées (pas pour un fichier venu du Finder).
    private func updateGroupPreview(_ info: DropInfo) {
        guard isPadDrag(info), let source = controller.draggedPosition else {
            controller.clearDragPreview()
            return
        }
        controller.updateDragPreview(source: source, target: position, copying: optionHeld)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        highlight = isPadDrag(info) && optionHeld ? .copy : .move
        updateGroupPreview(info)
        // Toujours « copier » : proposer « déplacer » à une source qui ne l'autorise pas fait refuser le dépôt
        // en silence. Le geste réel (déplacer, échanger, dupliquer avec ⌥) est décidé par `performDrop`.
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        highlight = nil
        controller.clearDragPreview()
    }

    func performDrop(info: DropInfo) -> Bool {
        highlight = nil
        controller.endDrag()
        Self.log.info("Glisser : dépôt sur \(position.description, privacy: .public), fichier \(info.hasItemsConforming(to: [.fileURL])), texte \(info.hasItemsConforming(to: [.plainText]))")
        let target = position
        let controller = controller

        // `itemProviders(for:)` renvoie aussi des fournisseurs qui n'ont pas ce type : on vérifie chacun.
        let providers = info.itemProviders(for: [.fileURL, .plainText])
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                guard let url else {
                    Self.log.error("Dépôt d'un fichier illisible : \(error?.localizedDescription ?? "URL absente")")
                    return
                }
                Task { @MainActor in controller.dropAudioFile(url, at: target) }
            }
            return true
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            let duplicate = optionHeld
            _ = provider.loadObject(ofClass: NSString.self) { object, error in
                guard let text = (object as? NSString).map({ $0 as String }) else {
                    Self.log.error("Glisser : texte illisible (\(error?.localizedDescription ?? "rien", privacy: .public))")
                    return
                }
                Task { @MainActor in
                    guard let token = PadDragToken.parse(text), token.grid == controller.currentGrid.id else {
                        Self.log.error("Glisser : jeton refusé « \(text, privacy: .public) »")
                        return
                    }
                    // Un pad de la sélection entraîne tout le groupe du même décalage ; sinon il est seul.
                    let done =
                        duplicate
                        ? controller.duplicateSelection(from: token.position, to: target)
                        : controller.moveSelection(from: token.position, to: target)
                    Self.log.info("Glisser : \(duplicate ? "duplication" : "déplacement", privacy: .public) \(token.position.description, privacy: .public) → \(target.description, privacy: .public) : \(done)")
                }
            }
            return true
        }
        return false
    }

    private func isPadDrag(_ info: DropInfo) -> Bool {
        !info.hasItemsConforming(to: [.fileURL])
    }
}

extension PlaybackState {
    fileprivate var isPaused: Bool {
        if case .paused = self { true } else { false }
    }

    /// Temps écoulé en secondes.
    fileprivate func elapsed(now: TimeInterval) -> TimeInterval {
        switch self {
        case .idle: 0
        case .playing(let startedAt): now - startedAt
        case .paused(let elapsed): elapsed
        }
    }
}
