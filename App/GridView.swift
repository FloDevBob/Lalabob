import AppKit
import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI
import UniformTypeIdentifiers
import os

/// La grille : 6 colonnes sons, une ligne de séparation ambrée, puis 2 colonnes lumière.
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

            // Zone lumière : plus de carte ni de fond, une simple ligne verticale ambrée la sépare des colonnes sons
            // (une zone fixe à droite, comme un panneau latéral qu'on ne referme pas).
            Rectangle()
                .fill(Surface.lightAccent.opacity(0.28))
                .frame(width: 1)
                .accessibilityHidden(true)

            HStack(spacing: Metrics.columnSpacing) {
                ForEach(indices(of: .light, in: grid), id: \.self) { index in
                    ColumnView(index: index, onPress: { focused = true })
                }
            }
            .frame(width: 264)
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
        // Espace : lecture / pause du pad sélectionné ; Retour : lecture / relance.
        // Pendant la saisie d'un titre (pad ou colonne), Espace et Retour appartiennent au champ de texte.
        .onKeyPress(.space, phases: .down) { _ in
            guard !Self.isTypingInTextField else { return .ignored }
            controller.togglePlaybackOfSelection()
            return .handled
        }
        .onKeyPress(.return, phases: .down) { _ in
            guard !Self.isTypingInTextField else { return .ignored }
            controller.playSelection()
            return .handled
        }
        // Flèches : d'un pad à l'autre ; Maj étend la sélection en rectangle (comme un Maj-clic).
        .onKeyPress(phases: [.down, .repeat]) { press in
            guard !Self.isTypingInTextField,
                press.modifiers.isDisjoint(with: [.command, .option, .control])
            else { return .ignored }
            let step: (dx: Int, dy: Int)
            switch press.key {
            case .leftArrow: step = (-1, 0)
            case .rightArrow: step = (1, 0)
            case .upArrow: step = (0, -1)
            case .downArrow: step = (0, 1)
            default: return .ignored
            }
            controller.moveSelection(dx: step.dx, dy: step.dy, extend: press.modifiers.contains(.shift))
            return .handled
        }
    }

    /// Un champ de texte a le focus (son éditeur de texte est le premier répondeur de la fenêtre).
    private static var isTypingInTextField: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    private func indices(of kind: ColumnKind, in grid: PadGrid) -> [Int] {
        grid.columns.indices.filter { grid.columns[$0].kind == kind }
    }
}

struct ColumnView: View {
    @Environment(\.gridDensity) private var density
    /// « 75 % · CC 54 » : le niveau et le CC que reçoit LightKey (sans CC tant qu'aucun contrôleur n'est connu).
    private func lightValueText(_ column: Column) -> String {
        let percent = Int((column.level * 100).rounded())
        guard let cc = controller.lightFaderCC(forColumn: index) else { return "\(percent) %" }
        return "\(percent) % · CC \(cc)"
    }

    @Environment(ShowController.self) private var controller
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    let onPress: () -> Void

    /// Appairage lumière : le fader d'une colonne lumière est lui aussi à rattacher à un réglage de LightKey.
    /// Pointillés ambrés (qui pulsent sur la cible), contour plein une fois appairé ; un clic sur l'étiquette désigne
    /// ce fader comme cible, bouger le fader (à la main ou à l'écran) envoie son CC à LightKey.
    @ViewBuilder
    private func faderPairingOverlay(_ column: Column) -> some View {
        if controller.isPairingLights, !controller.isLocked, column.kind == .light {
            let paired = column.isFaderPaired
            let isTarget = controller.pairingFader == index
            ZStack(alignment: .top) {
                if paired {
                    RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                        .strokeBorder(Surface.lightAccent.opacity(0.55), lineWidth: 1.5)
                } else if isTarget {
                    TimelineView(.animation(paused: reduceMotion)) { context in
                        let phase = reduceMotion ? 1 : 0.55 + 0.45 * sin(context.date.timeIntervalSinceReferenceDate * 4)
                        RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                            .strokeBorder(Surface.lightAccent.opacity(phase), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                } else {
                    RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                        .strokeBorder(Surface.lightAccent.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
                Button {
                    controller.selectPairingFader(column: index)
                } label: {
                    Text(paired ? "Appairé ✓" : isTarget ? "En attente…" : "Appairer")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(paired ? Surface.loopAccent : Surface.lightAccent, in: .capsule)
                        .foregroundStyle(Surface.window)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .padding(.top, 5)
                .interactiveCursor(.link)
                .help("Désigner ce fader comme cible, puis le bouger : son CC part vers LightKey")
                .accessibilityLabel(paired ? "Fader appairé" : "Appairer ce fader")
            }
        }
    }

    var body: some View {
        let column = controller.currentGrid.columns[index]
        VStack(spacing: Metrics.padSpacing) {
            HStack(spacing: 8) {
                // Pastille arrondie derrière l'icône (même principe que la carte d'astuce) : neutre pour les sons, ambrée pour la lumière.
                let isAudio = column.kind == .audio
                let tileTint = isAudio ? Surface.textSecondary : Surface.lightAccent
                RoundedRectangle(cornerRadius: 8)
                    .fill(tileTint.opacity(isAudio ? 0.12 : 0.14))
                    .frame(width: 26, height: 26)
                    .overlay { (isAudio ? Icon.music : Icon.spotlight).view(size: 15).foregroundStyle(tileTint) }
                    .accessibilityHidden(true)
                ColumnTitle(index: index, name: column.name)
                Spacer(minLength: 0)
                Text("\(index + 1)")
                    .font(Typography.mono)
                    .foregroundStyle(Surface.textTertiary)
            }
            .frame(height: 30)

            // Les 8 pads de la colonne : seuls eux défilent (comme une page) quand on change d'onglet.
            PadsPager(column: index, kind: column.kind, onPress: onPress)

            // Carte sous la colonne : un son a fader, vumètre du signal réel et dB ; une cue lumière a un fader
            // (CC envoyé à LightKey, comme le fader de l'Akai), un soleil qui suit le niveau, la valeur en % et le CC.
            Group {
                if column.kind == .audio {
                    VerticalFader(
                        name: column.name,
                        level: Binding(get: { column.level }, set: { controller.setColumnLevel(index, level: $0) }),
                        hardwareMarker: controller.waitingFaders[index]
                    ) {
                        LevelMeter(column: index).frame(width: 14)
                    }
                } else {
                    VerticalFader(
                        name: column.name,
                        level: Binding(get: { column.level }, set: { controller.setLightFader(column: index, level: $0) }),
                        valueText: lightValueText(column),
                        defaultLevel: 1,
                        hardwareMarker: controller.waitingFaders[index]
                    ) {
                        Icon.sun.view(size: 16)
                            .foregroundStyle(Surface.lightAccent)
                            .opacity(0.25 + 0.75 * column.level)
                            .frame(width: 16, height: density.faderTrackHeight, alignment: .top)
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
            .overlay { faderPairingOverlay(column) }
            .padding(.top, 4)
        }
        .frame(minWidth: 110, maxWidth: .infinity)
    }
}

/// Les 8 pads d'une colonne, vus comme une page : quand on change de grille, la nouvelle page défile depuis le bas et
/// l'ancienne sort par le haut si on avance dans les onglets (depuis le haut et par le bas si on recule), comme le
/// défilement d'une grande page web. Seuls les pads bougent : noms de colonnes et cartes de volume restent en place.
///
/// La page affichée est mémorisée ici (`displayedGridID`) et non lue sur la grille courante : au changement d'onglet,
/// l'ancienne page reste à l'écran jusqu'à ce que le mouvement commence (pas d'image intermédiaire avec les pads de la
/// nouvelle grille à leur place). L'ancienne page n'est plus qu'une image de l'ancienne grille, sans interaction.
/// Pas de recréation de la grille : le focus clavier (⌘C, ⌘V…) est conservé. Sans mouvement si « Réduire les animations ».
struct PadsPager: View {
    @Environment(ShowController.self) private var controller
    @Environment(\.gridDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let column: Int
    let kind: ColumnKind
    let onPress: () -> Void

    @State private var displayedGridID: PadGrid.ID?
    @State private var outgoing: PadGrid?
    /// +1 : on avance (la nouvelle page arrive par le bas) ; -1 : on recule (elle arrive par le haut).
    @State private var direction: CGFloat = 1
    /// 0 : début du défilement, 1 : terminé.
    @State private var progress: CGFloat = 1
    @State private var changeCount = 0

    private var height: CGFloat {
        CGFloat(PadGrid.size) * density.padHeight + CGFloat(PadGrid.size - 1) * Metrics.padSpacing
    }

    private var displayedGrid: PadGrid {
        controller.show.grids.first { $0.id == displayedGridID } ?? controller.currentGrid
    }

    var body: some View {
        ZStack {
            if let outgoing {
                page(outgoing, isInteractive: false)
                    .offset(y: -direction * progress * height)
                    .opacity(1 - 0.5 * progress)
            }
            page(displayedGrid, isInteractive: true)
                .offset(y: direction * (1 - progress) * height)
                .opacity(0.5 + 0.5 * progress)
        }
        .frame(height: height)
        // Coupe ce qui sort de la colonne, mais laisse la lueur d'un pad en lecture déborder un peu.
        .mask(Rectangle().padding(EdgeInsets(top: -Metrics.padSpacing, leading: -10, bottom: -Metrics.padSpacing, trailing: -10)))
        .onAppear { displayedGridID = controller.currentGrid.id }
        .onChange(of: controller.currentGrid.id) { oldID, newID in change(from: oldID, to: newID) }
    }

    private func page(_ grid: PadGrid, isInteractive: Bool) -> some View {
        VStack(spacing: Metrics.padSpacing) {
            ForEach(0..<PadGrid.size, id: \.self) { row in
                PadView(
                    position: GridPosition(column: column, row: row), kind: kind, grid: grid,
                    isInteractive: isInteractive, onPress: onPress)
            }
        }
    }

    private func change(from oldID: PadGrid.ID, to newID: PadGrid.ID) {
        let grids = controller.show.grids
        guard !reduceMotion, let oldGrid = grids.first(where: { $0.id == oldID }),
            let oldIndex = grids.firstIndex(where: { $0.id == oldID }),
            let newIndex = grids.firstIndex(where: { $0.id == newID })
        else {
            outgoing = nil
            displayedGridID = newID  // grille supprimée, annulation… : on affiche tout de suite la nouvelle
            return
        }
        // Ce qui est vraiment à l'écran (si un mouvement précédent n'est pas fini, c'est la page affichée, pas l'ancienne).
        outgoing = displayedGrid.id == oldID ? displayedGrid : oldGrid
        displayedGridID = newID
        direction = newIndex > oldIndex ? 1 : -1
        progress = 0
        changeCount += 1
        let thisChange = changeCount
        withAnimation(Motion.pageScroll) {
            progress = 1
        } completion: {
            if changeCount == thisChange { outgoing = nil }
        }
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
                    .help(HelpText.rename("la colonne", locked: controller.isLocked))
                    .interactiveCursor(.horizontalText, enabled: !controller.isLocked)
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
    @Environment(\.gridDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let kind: ColumnKind
    /// La grille dont on affiche la case (celle de la page à l'écran, pas forcément la grille courante pendant un défilement).
    let grid: PadGrid
    /// `false` : simple image de l'ancienne page pendant un défilement (ni clic, ni glisser, ni menu).
    var isInteractive = true
    let onPress: () -> Void
    @State private var dropHighlight: DropHighlight?
    /// Le titre ou le sous-titre est en cours de modification (le curseur de la case reste une flèche pendant la saisie).
    @State private var editingField: InlinePadText.Field?
    private var isEditingText: Bool { editingField != nil }

    @ViewBuilder
    var body: some View {
        if isInteractive {
            interactiveBody
        } else {
            Group {
                if let pad = grid[position] { filled(pad, event: nil) } else { empty }
            }
            .frame(height: density.padHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var interactiveBody: some View {
        let pad = grid[position]
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
        .frame(height: density.padHeight)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Metrics.padCornerRadius).stroke(.white, lineWidth: 2)
            }
        }
        .overlay { pairingOverlay }
        .overlay { dropOverlay }
        .overlay { groupDropOverlay }
        .contentShape(.rect(cornerRadius: Metrics.padCornerRadius))
        // Verrouillé ou non : un clic sélectionne (le panneau s'ouvre), un double-clic joue. Le contrôleur, lui, joue d'un appui.
        .onTapGesture(count: 2) { controller.audition(at: position) }
        .simultaneousGesture(TapGesture().onEnded(activate))
        // Pas de `!isEditingText` ici : faire basculer ce modificateur change la structure de la vue, SwiftUI recrée alors le
        // titre en cours de modification et son champ s'ouvre vide (et sans focus).
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
        // Main ouverte : le pad peut être saisi et glissé (déplacer, ⌥ pour copier). Flèche sinon.
        .interactiveCursor(.grabIdle, enabled: pad != nil && !controller.isLocked && !isEditingText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pad.map { "\($0.title), \($0.subtitle)" } ?? (kind == .audio ? "Case vide" : "Case lumière vide"))
        .accessibilityValue(lightAccessibilityValue(pad))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { controller.audition(at: position) }
        .accessibilityAction(named: "Sélectionner") { activate() }
        .help(padHelp(pad))
    }

    /// Appairage lumière : contour pointillé ambré pulsant sur la case cible en attente, contour plein sur une case appairée,
    /// ampoule cliquable (envoie la note à LightKey) sur toutes les cases lumière.
    @ViewBuilder
    private var pairingOverlay: some View {
        if controller.isPairingLights, !controller.isLocked, kind == .light {
            let paired = controller.isPaired(at: position)
            let isTarget = controller.selection == position
            ZStack(alignment: .bottomTrailing) {
                if paired {
                    RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                        .strokeBorder(Surface.lightAccent.opacity(0.55), lineWidth: 1.5)
                } else if isTarget {
                    TimelineView(.animation(paused: reduceMotion)) { context in
                        let phase = reduceMotion ? 1 : 0.55 + 0.45 * sin(context.date.timeIntervalSinceReferenceDate * 4)
                        RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                            .strokeBorder(Surface.lightAccent.opacity(phase), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                } else {
                    RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                        .strokeBorder(Surface.lightAccent.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
                Button {
                    controller.pairingSend(at: position)
                } label: {
                    Icon.lightbulb.view(size: 13)
                        .frame(width: 22, height: 22)
                        .background(Surface.lightAccent, in: .circle)
                        .foregroundStyle(Surface.window)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .padding(5)
                .interactiveCursor(.link)
                .help("Envoyer la note de cette case à LightKey")
                .accessibilityLabel("Envoyer la note à LightKey")
            }
        }
    }

    private func lightAccessibilityValue(_ pad: Pad?) -> String {
        if controller.isPairingLights, !controller.isLocked, kind == .light {
            return controller.isPaired(at: position) ? "Appairée" : "À appairer"
        }
        guard pad?.kind == .light else { return "" }
        switch controller.lightState(at: position) {
        case .on: return "Allumée"
        case .off: return "Éteinte"
        case .unknown: return ""
        }
    }

    private func padHelp(_ pad: Pad?) -> String {
        if pad != nil {
            return controller.isLocked
                ? "Clic : sélectionner · Double-clic : jouer"
                : "Clic : sélectionner · Double-clic : jouer · Glisser : déplacer (⌥ : copier)"
        }
        guard !controller.isLocked else { return "" }
        return kind == .audio ? "Glissez un son ici (depuis la bibliothèque ou le Finder)" : "Case lumière vide : sélectionnez-la pour créer une cue"
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
        let lightState: LightState = pad.kind == .light ? controller.lightState(at: position) : .unknown
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                InlinePadText(position: position, field: .title, text: pad.title, font: Typography.padTitle, editing: $editingField)
                Spacer(minLength: 0)
                if lightState != .unknown {
                    Icon.lightbulb.view(size: 13)
                        .foregroundStyle(lightState == .on ? vivid : pad.tint.labelColor.opacity(0.4))
                }
                if case .paused = event?.state { Icon.pause.view(size: 12) }
                if case .playing = event?.state { MiniEqualizer(color: pad.tint.vividColor, isAnimating: true) }
                if case .audio = pad.content { playStopButton(pad, event: event) }
            }
            InlinePadText(position: position, field: .subtitle, text: pad.subtitle, font: Typography.padSubtitle, editing: $editingField)
                .opacity(0.88)
        }
        .foregroundStyle(pad.tint.labelColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .background(pad.tint.surfaceColor, in: .rect(cornerRadius: Metrics.padCornerRadius))
        // Relief : liseré clair en haut du pad, qui s'estompe avant le milieu (simple décor, sous les contours d'état).
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.16), location: 0),
                            .init(color: .white.opacity(0.03), location: 0.3),
                            .init(color: .clear, location: 0.5),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) { progressBar(event, color: vivid) }
        .overlay {
            if let event {
                RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                    .stroke(vivid.opacity(event.state.isPaused ? 0.45 : 1), lineWidth: 2)
            } else if lightState == .on {
                RoundedRectangle(cornerRadius: Metrics.padCornerRadius).stroke(vivid, lineWidth: 2)
            }
        }
        .shadow(
            color: event.map { $0.state.isPaused ? .clear : vivid.opacity(0.45) } ?? (lightState == .on ? vivid.opacity(0.45) : .clear),
            radius: 8)
    }

    /// Bouton à deux états à côté de l'égaliseur : triangle (lecture) tant que le son est à l'arrêt ou en pause,
    /// carré (stop) quand il joue. Un vrai `Button` : seule sa petite zone capte la souris, le reste du pad garde
    /// son clic / double-clic / glisser.
    private func playStopButton(_ pad: Pad, event: PlaybackEvent?) -> some View {
        let isPlaying: Bool = if case .playing = event?.state { true } else { false }
        return Button {
            controller.togglePlayStop(at: position)
        } label: {
            (isPlaying ? Icon.stop : Icon.play).view(size: 10)
                .frame(width: 20, height: 20)
                .background(isPlaying ? pad.tint.vividColor : pad.tint.labelColor.opacity(0.18), in: .circle)
                .foregroundStyle(isPlaying ? pad.tint.surfaceColor : pad.tint.labelColor)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .interactiveCursor(.link)
        .help(isPlaying ? "Arrêter ce son" : event?.state.isPaused == true ? "Reprendre ce son" : "Lancer ce son")
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

/// Titre ou sous-titre d'un pad, modifiable sur place par un double-clic quand le spectacle est déverrouillé
/// (Entrée ou clic ailleurs valide, Échap annule). Verrouillé, c'est un simple texte : le double-clic joue le pad.
struct InlinePadText: View {
    enum Field { case title, subtitle }

    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let field: Field
    let text: String
    let font: Font
    /// Le champ en cours de modification sur ce pad (un seul à la fois).
    @Binding var editing: Field?
    private var isEditing: Bool { editing == field }

    @State private var draft = ""
    /// Position du curseur : à la fin du texte à l'ouverture (sinon macOS sélectionne tout).
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField(field == .title ? "Titre" : "Sous-titre", text: $draft, selection: $selection)
                    .textFieldStyle(.plain)
                    .font(font)
                    .focused($focused)
                    .padding(.horizontal, 3)
                    .background(Color.white.opacity(0.14), in: .rect(cornerRadius: 4))
                    .onSubmit { focused = false }
                    .onExitCommand { cancel() }
                    .onChange(of: focused) { wasFocused, isFocused in
                        if wasFocused, !isFocused { commit() }
                    }
            } else if controller.isLocked {
                label
            } else {
                label
                    .contentShape(.rect)
                    .interactiveCursor(.horizontalText)
                    .help(HelpText.rename(field == .title ? "le titre" : "le sous-titre", locked: false))
                    // Le double-clic sur le texte modifie ; ailleurs sur le pad, il joue.
                    .onTapGesture(count: 2) { start() }
            }
        }
        // Appairage lumière : la cue qui vient d'être appairée demande son nom ; la saisie finie, la case suivante s'arme.
        .onAppear { startForPairingIfNeeded() }
        .onChange(of: controller.pairingNaming) { startForPairingIfNeeded() }
        .onChange(of: editing) { old, new in
            if field == .title, old == .title, new == nil, controller.pairingNaming == position {
                controller.finishPairingNaming()
            }
        }
        // Verrouiller, changer de case ou de grille pendant la saisie l'abandonne.
        .onChange(of: controller.isLocked) { cancel() }
        .onChange(of: position) { cancel() }
        .onChange(of: controller.selectedGridIndex) { cancel() }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            // Un sous-titre vide garde sa ligne : on peut toujours double-cliquer pour en écrire un.
            .frame(minWidth: 24, minHeight: 14, alignment: .leading)
    }

    private func startForPairingIfNeeded() {
        guard field == .title, controller.pairingNaming == position, !isEditing else { return }
        start(selectingAll: true)
    }

    /// `selectingAll` : tout le texte est sélectionné (le nom proposé se remplace d'une frappe).
    private func start(selectingAll: Bool = false) {
        guard !controller.isLocked else { return }
        draft = text
        selection = nil
        editing = field
        Task { @MainActor in
            focused = true
            // macOS sélectionne tout le texte quand le champ prend le focus : le curseur passe à la fin juste après.
            try? await Task.sleep(for: .milliseconds(40))
            guard editing == field else { return }
            selection =
                selectingAll
                ? TextSelection(range: draft.startIndex..<draft.endIndex) : TextSelection(insertionPoint: draft.endIndex)
        }
    }

    private func cancel() {
        guard isEditing else { return }
        editing = nil
        focused = false
    }

    private func commit() {
        guard isEditing else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        switch field {
        case .title: if !trimmed.isEmpty { controller.updatePad(at: position, title: trimmed) }
        case .subtitle: controller.updatePad(at: position, subtitle: trimmed)
        }
        editing = nil
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
