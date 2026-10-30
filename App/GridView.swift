import AppKit
import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI
import UniformTypeIdentifiers
import os

/// La grille : 6 colonnes sons, puis 2 colonnes lumière dans une zone ambrée.
/// Elle reçoit ⌘X / ⌘C / ⌘V / ⌫ quand elle a le focus (un clic sur un pad le lui donne).
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
            .padding(8)
            .background(Surface.lightZone, in: .rect(cornerRadius: Metrics.panelCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.panelCornerRadius)
                    .stroke(Surface.lightAccent.opacity(0.12))
            )
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
    @Environment(ShowController.self) private var controller
    let index: Int
    let onPress: () -> Void

    var body: some View {
        let column = controller.currentGrid.columns[index]
        VStack(spacing: Metrics.padSpacing) {
            HStack(spacing: 8) {
                Image(systemName: column.kind == .audio ? "music.note" : "lightbulb.max.fill")
                    .foregroundStyle(column.kind == .audio ? Surface.textSecondary : Surface.lightAccent)
                Text(column.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Surface.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(index + 1)")
                    .font(Typography.mono)
                    .foregroundStyle(Surface.textTertiary)
            }
            .frame(height: 30)

            ForEach(0..<PadGrid.size, id: \.self) { row in
                PadView(position: GridPosition(column: index, row: row), kind: column.kind, onPress: onPress)
            }

            if column.kind == .audio {
                // Fader provisoire (horizontal) ; le fader vertical de la maquette arrive au jalon 5.
                Slider(value: Binding(get: { column.level }, set: { controller.setColumnLevel(index, level: $0) }), in: 0...1)
                    .controlSize(.small)
                    .accessibilityLabel("Volume de \(column.name)")
            }
        }
        .frame(minWidth: 110, maxWidth: .infinity)
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
        let isSelected = controller.selection == position

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
        .contentShape(.rect(cornerRadius: Metrics.padCornerRadius))
        .onTapGesture(perform: activate)
        .onDrag {
            guard pad != nil else { return NSItemProvider() }
            let token = PadDragToken.string(grid: controller.currentGrid.id, position: position)
            PadDropDelegate.log.info("Glisser : départ de \(position.description, privacy: .public)")
            return NSItemProvider(object: token as NSString)
        }
        .onDrop(
            of: [.fileURL, .plainText],
            delegate: PadDropDelegate(position: position, controller: controller, highlight: $dropHighlight)
        )
        .contextMenu {
            if pad != nil, kind == .audio {
                Button("Pause / Reprendre") { controller.togglePause(at: position) }
                Button("Arrêter") { controller.stop(at: position) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pad.map { "\($0.title), \($0.subtitle)" } ?? (kind == .audio ? "Case vide" : "Case lumière vide"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { activate() }
    }

    private func activate() {
        onPress()
        controller.press(at: position)
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
                if case .paused = event?.state { Image(systemName: "pause.fill").font(.system(size: 10)) }
                if case .playing = event?.state { Image(systemName: "waveform").font(.system(size: 10)) }
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
        Label(kind == .audio ? "Déposer un son" : "Nouvelle cue", systemImage: "plus")
            .font(.system(size: 11.5))
            .foregroundStyle(Surface.textTertiary)
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
    static let log = Logger(subsystem: "fr.lalabob.app", category: "drop")

    let position: GridPosition
    let controller: ShowController
    @Binding var highlight: DropHighlight?

    private var optionHeld: Bool { NSEvent.modifierFlags.contains(.option) }

    func validateDrop(info: DropInfo) -> Bool {
        let valid = info.hasItemsConforming(to: [.fileURL, .plainText])
        Self.log.info("Glisser : validation sur \(position.description, privacy: .public) → \(valid)")
        return valid
    }

    func dropEntered(info: DropInfo) {
        Self.log.info("Glisser : entrée sur \(position.description, privacy: .public)")
        highlight = isPadDrag(info) && optionHeld ? .copy : .move
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        highlight = isPadDrag(info) && optionHeld ? .copy : .move
        // Toujours « copier » : proposer « déplacer » à une source qui ne l'autorise pas fait refuser le dépôt
        // en silence. Le geste réel (déplacer, échanger, dupliquer avec ⌥) est décidé par `performDrop`.
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        highlight = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        highlight = nil
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
                    let done =
                        duplicate
                        ? controller.duplicatePad(from: token.position, to: target)
                        : controller.movePad(from: token.position, to: target)
                    Self.log.info("Glisser : \(duplicate ? "duplication" : "déplacement", privacy: .public) \(token.position.description, privacy: .public) → \(target.description, privacy: .public) : \(done)")
                    if done { controller.selection = target }
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
