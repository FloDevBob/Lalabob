import AppKit
import LalabobDMX
import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI
import UniformTypeIdentifiers
import os

/// La grille : 8 colonnes de **même largeur**, dans leur ordre réel. Le type de chaque colonne (son ou lumière) se lit dans
/// la pastille et le liseré de son en-tête (`ColumnView`). Elle reçoit ⌘X / ⌘C / ⌘V / ⌫ quand elle a le focus (un clic sur un pad le lui donne) ;
/// verrouillée, ces commandes sont refusées par `ShowController` avec un message.
struct GridView: View {
    @Environment(ShowController.self) private var controller
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.columnSpacing) {
            ForEach(0..<PadGrid.size, id: \.self) { index in
                ColumnView(index: index, onPress: { focused = true })
                    .frame(maxWidth: .infinity)
            }
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

}

struct ColumnView: View {
    @Environment(\.gridDensity) private var density
    /// Incrémenté par « Renommer… » du menu : le titre passe en saisie.
    @State private var renameRequest = 0
    /// « Intensité 75 % » : l'intensité des projecteurs de la colonne (le CC MIDI n'est pas affiché, voir docs/LEXIQUE.md).
    private func lightValueText(_ column: Column) -> String {
        let percent = Int((column.level * 100).rounded())
        guard controller.isDMXLighting else { return "Intensité \(percent) %" }
        // Mode Projecteurs : le fader a un rôle (Intensité, Couleurs, Strobo), écrit sur la carte.
        let role = DMXFaderRole.role(ofColumn: index, in: controller.currentGrid)
        return "\(percent) %"
    }

    @Environment(ShowController.self) private var controller
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    let onPress: () -> Void

    /// Clic droit sur la carte d'un fader lumière (mode Projecteurs) : ce que règle ce fader.
    @ViewBuilder
    private func faderRoleMenu(current: DMXFaderRole) -> some View {
        Section("Ce que règle ce fader") {
            ForEach(DMXFaderRole.allCases, id: \.self) { role in
                Button {
                    controller.setFaderRole(column: index, to: role)
                } label: {
                    Text((role == current ? "✓ " : "") + role.title)
                }
            }
        }
    }

    /// Petit bouton « stop » à côté du volume d'une colonne son : arrête tous les sons de la colonne. Sur l'APC mini mk2,
    /// le bouton rond rouge sous la colonne fait la même chose. Les colonnes lumière n'en ont pas.
    private var stopColumnButton: some View {
        Button {
            controller.stopColumn(index)
        } label: {
            Icon.stopFill.view(size: 12)
                .frame(width: 28, height: 28)
                .background(Color.red.opacity(0.85), in: .circle)
                .foregroundStyle(.white)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .padding(6)
        .interactiveCursor(.link)
        .help("Arrêter tous les sons de cette colonne")
        .accessibilityLabel("Arrêter la colonne \(index + 1)")
    }

    /// Couleur d'une colonne son : la teinte vive de son premier pad (gris neutre si elle est vide).
    private func accentColor(of column: Column) -> Color {
        column.slots.lazy.compactMap { $0 }.first?.tint.vividColor ?? Surface.textSecondary
    }

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
                    Text(paired ? "Relié ✓" : isTarget ? "En attente…" : "Relier")
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
                .help("Choisir ce fader, puis le bouger : le logiciel des projecteurs apprend qu'il règle cette intensité")
                .accessibilityLabel(paired ? "Fader relié aux projecteurs" : "Relier ce fader aux projecteurs")
            }
        }
    }

    var body: some View {
        let column = controller.currentGrid.columns[index]
        VStack(spacing: Metrics.padSpacing) {
            HStack(spacing: 8) {
                // Pastille de type : note (son), projecteur (lumière), les deux (son et lumière) ; un bouton déverrouillé.
                ColumnKindPill(index: index, kind: column.kind, name: column.name)
                ColumnTitle(index: index, name: column.name, renameTrigger: renameRequest)
                Spacer(minLength: 0)
                Text("\(index + 1)")
                    .font(Typography.mono)
                    .foregroundStyle(Surface.textTertiary)
            }
            .frame(height: 30)
            // Liseré de type sous l'en-tête (dans la hauteur de l'en-tête : les pads ne bougent pas) : discret pour un son,
            // ambre plein pour la lumière, ambre pointillé pour son et lumière.
            .overlay(alignment: .bottom) { ColumnKindRule(kind: column.kind) }
            .contextMenu { ColumnContextMenu(index: index, rename: { renameRequest += 1 }) }

            // Les 8 pads de la colonne : seuls eux défilent (comme une page) quand on change d'onglet.
            PadsPager(column: index, kind: column.kind, onPress: onPress)

            // Carte sous la colonne : un son a fader, vumètre du signal réel et dB ; une cue lumière a un fader
            // (CC envoyé à LightKey, comme le fader de l'Akai), un soleil qui suit le niveau, la valeur en % et le CC.
            Group {
                if column.kind == .music, controller.musicPlayer?.isBridgeEnabled != true {
                    // Colonne Music : pas de fader (le volume est celui de Music, réglé par le 9e fader de l'APC).
                    VStack(alignment: .leading, spacing: 6) {
                        IconLabel("Volume", icon: .volume, size: 12)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Surface.textTertiary)
                        Text("Réglé par le 9e fader de l'APC (Apple Music)")
                            .font(.system(size: 11))
                            .foregroundStyle(Surface.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: density.faderTrackHeight, alignment: .topLeading)
                    .accessibilityElement(children: .combine)
                } else if column.kind.hasAudio || column.kind == .music {  // son, mixte, ou Music par le pont audio
                    HStack(alignment: .top, spacing: 8) {
                        VerticalFader(
                            name: column.name,
                            level: Binding(get: { column.level }, set: { controller.setColumnLevel(index, level: $0) }),
                            hardwareMarker: controller.waitingFaders[index]
                        ) {
                            LevelMeter(column: index).frame(width: 14)
                        }
                        // Filtre DJ de la colonne (passe-bas à gauche, passe-haut à droite), arc à la couleur de la colonne.
                        RotaryKnob(
                            name: column.name,
                            accent: accentColor(of: column),
                            value: Binding(get: { column.filter }, set: { controller.setColumnFilter(index, value: $0) }),
                            onReset: { controller.resetColumnFilter(index) }
                        )
                    }
                } else {
                    let role = controller.isDMXLighting ? DMXFaderRole.role(ofColumn: index, in: controller.currentGrid) : nil
                    VerticalFader(
                        name: column.name,
                        level: Binding(get: { column.level }, set: { controller.setLightFader(column: index, level: $0) }),
                        valueText: lightValueText(column),
                        defaultLevel: 1,
                        hardwareMarker: controller.waitingFaders[index]
                    ) {
                        if let role {
                            // Mode Projecteurs (piste C de la maquette) : le rôle du fader ; la carte Intensité porte la mini-barre.
                            DMXFaderAccessory(column: index, role: role)
                        } else {
                            Icon.sun.view(size: 16)
                                .foregroundStyle(Surface.lightAccent)
                                .opacity(0.25 + 0.75 * column.level)
                                .frame(width: 16, height: density.faderTrackHeight, alignment: .top)
                        }
                    }
                    .opacity(role == DMXFaderRole.none ? 0.5 : 1)
                    .contextMenu { if role != nil, !controller.isLocked { faderRoleMenu(current: role ?? .none) } }
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
            .overlay(alignment: .bottomTrailing) { if column.kind.hasAudio || column.kind == .music { stopColumnButton } }
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
    /// Un changement de valeur (menu « Renommer… ») ouvre la saisie du nom.
    var renameTrigger = 0

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
        .onChange(of: renameTrigger) { start() }
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
    @Environment(MusicLibraryController.self) private var musicLibrary: MusicLibraryController?
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
        .accessibilityLabel(
            pad.map { "\($0.title), \($0.subtitle)" + ($0.kind == .mixed ? ", son et lumière" : "") }
                ?? (kind == .music ? "Case Music vide" : kind.hasAudio ? "Case vide" : "Case lumière vide")
        )
        .accessibilityValue(accessibilityValue(pad, event: event))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { controller.audition(at: position) }
        .accessibilityAction(named: "Sélectionner") { activate() }
        .accessibilityAction(named: "Essayer la lumière") { controller.testCue(at: position) }
        .help(padHelp(pad))
    }

    /// Appairage lumière : contour pointillé ambré pulsant sur la case cible en attente, contour plein sur une case appairée,
    /// ampoule cliquable (envoie la note à LightKey) sur toutes les cases lumière.
    @ViewBuilder
    private var pairingOverlay: some View {
        if controller.isPairingLights, !controller.isLocked, controller.isLightCell(position) {
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
                // Une cue a déjà son bouton rond dans le pad ; une case libre reçoit le même, en ambre.
                if controller.pad(at: position) == nil {
                    Button {
                        controller.pairingSend(at: position)
                    } label: {
                        Icon.lightbulbFill.view(size: Self.buttonSize(for: density) * 0.5)
                            .frame(width: Self.buttonSize(for: density), height: Self.buttonSize(for: density))
                            .background(Surface.lightAccent, in: .circle)
                            .foregroundStyle(Surface.window)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .interactiveCursor(.link)
                    .help("Envoyer le signal de cette case au logiciel des projecteurs, pour la relier")
                    .accessibilityLabel("Envoyer le signal de cette case")
                }
            }
        }
    }

    /// Pad son et lumière : « En lecture, cue allumée ». Un pad son ou lumière seul : son état, ou celui de sa cue.
    private func accessibilityValue(_ pad: Pad?, event: PlaybackEvent?) -> String {
        var parts: [String] = []
        if case .playing = event?.state { parts.append("En lecture") } else if event?.state.isPaused == true { parts.append("En pause") }
        let light = lightAccessibilityValue(pad)
        if !light.isEmpty { parts.append(pad?.audio != nil ? "lumière " + light.lowercased() : light) }
        return parts.joined(separator: ", ")
    }

    private func lightAccessibilityValue(_ pad: Pad?) -> String {
        if controller.isPairingLights, !controller.isLocked, controller.isLightCell(position) {
            return controller.isPaired(at: position) ? "Reliée" : "À relier"
        }
        guard pad?.light != nil else { return "" }
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
        if kind == .music { return "Glissez ici un morceau d'une playlist d'Apple Music (panneau de gauche)" }
        if kind == .mixed { return "Glissez un son ici (bibliothèque ou Finder), ou cliquez « + Lumière » pour créer une lumière" }
        return kind.hasAudio ? "Glissez un son ici (depuis la bibliothèque ou le Finder)" : "Case lumière vide : sélectionnez-la pour créer une lumière"
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
        if let index = controller.musicDropPreview.firstIndex(of: position) {
            RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                        .strokeBorder(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
                .overlay {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Surface.musicAccent, in: .circle)
                        .foregroundStyle(Surface.window)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if let preview = controller.dragPreview, preview.positions.contains(position) {
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
        let lightState: LightState = pad.light != nil ? controller.lightState(at: position) : .unknown
        let outline: Double = event.map { $0.state.isPaused ? 0.45 : 1 } ?? (lightState == .on ? 1 : 0)
        let halo: Double = event.map { $0.state.isPaused ? 0 : 0.45 } ?? (lightState == .on ? 0.45 : 0)
        // Texte (titre + sous-titre serrés) à gauche, état et bouton à droite : tout est centré sur le même axe horizontal.
        return HStack(spacing: Self.contentSpacing) {
            VStack(alignment: .leading, spacing: 1) {
                InlinePadText(position: position, field: .title, text: pad.title, font: Typography.padTitle, editing: $editingField)
                if pad.subtitle.isEmpty, let summary = lookSummary(pad) {
                    // Pas de sous-titre : en mode Projecteurs, l'état lumineux se résume (« Ensemble · 2 et 3 »).
                    Text(summary.subtitle).font(Typography.padSubtitle).lineLimit(1).opacity(0.88)
                } else {
                    InlinePadText(position: position, field: .subtitle, text: pad.subtitle, font: Typography.padSubtitle, editing: $editingField)
                        .opacity(0.88)
                }
            }
            Spacer(minLength: 0)
            if case .paused = event?.state { Icon.pauseFill.view(size: 14) }
            if case .playing = event?.state { MiniEqualizer(color: pad.tint.vividColor, isAnimating: true) }
            if pad.music != nil {
                musicAvailabilityBadge(pad)
                musicButton(pad, event: event)
            } else if pad.audio != nil, pad.light != nil {
                mixedCapsule(pad, event: event, state: lightState)
            } else {
                if pad.audio != nil { playStopButton(pad, event: event) }
                if let summary = lookSummary(pad) {
                    // Mode Projecteurs : les points des projecteurs SONT le bouton (clic = allumer, second clic = éteindre).
                    ProjectorToggle(
                        summary: summary, tint: pad.tint, isOn: lightState == .on, compact: density.padHeight < 44,
                        action: {
                            if controller.isPairingLights, !controller.isLocked { controller.pairingSend(at: position) } else { controller.toggleLight(at: position) }
                        })
                } else if pad.light != nil {
                    cueButton(pad, state: lightState)
                }
            }
        }
        .foregroundStyle(pad.tint.labelColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, Self.horizontalInset)
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
            RoundedRectangle(cornerRadius: Metrics.padCornerRadius).stroke(vivid.opacity(outline), lineWidth: 2)
        }
        // « Son et lumière » choisi, son pas encore déposé : un badge ambre invite à déposer un fichier (masqué sur un pad bas).
        .overlay(alignment: .topTrailing) {
            if pad.awaitsSound, density.padHeight >= 50 {
                Text("+ Son")
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Surface.lightAccent, in: .capsule)
                    .foregroundStyle(Surface.window)
                    .padding(.top, 3)
                    .padding(.trailing, 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .shadow(color: vivid.opacity(halo), radius: 8)
        // La lueur s'éteint en fondu (0,35 s) quand le son s'arrête ; à l'allumage rien n'est animé.
        .animation(reduceMotion || outline > 0 ? nil : Motion.glowOut, value: outline)
    }

    /// Le résumé de l'état lumineux d'un pad, en mode Projecteurs seulement.
    private func lookSummary(_ pad: Pad) -> LightLookSummary? {
        guard controller.isDMXLighting, pad.audio == nil, pad.music == nil else { return nil }
        return pad.light?.look?.summary
    }

    /// Bouton rond d'une cue lumière, du même dessin que le bouton lecture d'un son : une ampoule pleine qui envoie la cue
    /// à LightKey (comme un double-clic ; marche aussi verrouillé). Sa couleur dit l'état renvoyé par LightKey : pleine
    /// couleur du pad = allumée, atténuée = éteinte, neutre = LightKey n'a encore rien dit. En mode d'appairage, il envoie
    /// la note et désigne la case comme cible.
    private func cueButton(_ pad: Pad, state: LightState, size: CGFloat? = nil, inCapsule: Bool = false) -> some View {
        let size = size ?? Self.buttonSize(for: density)
        let isOn = state == .on
        let isOff = state == .off
        let idleBackground: Color = inCapsule ? .clear : pad.tint.labelColor.opacity(isOff ? 0.10 : 0.18)
        return Button {
            if controller.isPairingLights, !controller.isLocked {
                controller.pairingSend(at: position)
            } else {
                controller.testCue(at: position)  // la cue seule : le son d'un pad son et lumière ne part pas
            }
        } label: {
            Icon.lightbulbFill.view(size: size * 0.5)
                .frame(width: size, height: size)
                .background(isOn ? pad.tint.vividColor : idleBackground, in: .circle)
                .foregroundStyle(isOn ? pad.tint.surfaceColor : pad.tint.labelColor.opacity(isOff ? 0.55 : 1))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .interactiveCursor(.link)
        .help(
            controller.isPairingLights
                ? "Envoyer le signal de cette case au logiciel des projecteurs, pour la relier"
                : pad.audio != nil
                    ? "Essayer la lumière, sans lancer le son"
                    : "Allumer ou éteindre la lumière (double-clic sur le pad : pareil)"
        )
        .accessibilityLabel(controller.isPairingLights ? "Envoyer le signal de cette case" : "Essayer la lumière")
        .accessibilityValue(isOn ? "Allumée" : isOff ? "Éteinte" : "")
    }

    /// Diamètre du bouton lecture / stop d'un pad : le plus grand que la hauteur du pad permet (titre + sous-titre
    /// restent visibles), de 22 pt dans une petite fenêtre à 30 pt.
    /// Marge gauche = droite du contenu d'un pad ; espace entre le bloc de texte et les éléments de droite.
    private static let horizontalInset: CGFloat = 11
    private static let contentSpacing: CGFloat = 6

    private static func buttonSize(for density: GridDensity) -> CGFloat {
        density.padHeight >= 52 ? 30 : density.padHeight >= 44 ? 26 : 22
    }

    /// Bouton à deux états à côté de l'égaliseur : triangle (lecture) tant que le son est à l'arrêt ou en pause,
    /// carré (stop) quand il joue. Un vrai `Button` : seule sa petite zone capte la souris, le reste du pad garde
    /// son clic / double-clic / glisser.
    private func playStopButton(_ pad: Pad, event: PlaybackEvent?, size: CGFloat? = nil, inCapsule: Bool = false) -> some View {
        let isPlaying: Bool = if case .playing = event?.state { true } else { false }
        let size = size ?? Self.buttonSize(for: density)
        return Button {
            controller.togglePlayStop(at: position)
        } label: {
            (isPlaying ? Icon.stopFill : Icon.playFill).view(size: size * 0.5)
                .frame(width: size, height: size)
                .background(isPlaying ? pad.tint.vividColor : inCapsule ? Color.clear : pad.tint.labelColor.opacity(0.18), in: .circle)
                .foregroundStyle(isPlaying ? pad.tint.surfaceColor : pad.tint.labelColor)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .interactiveCursor(.link)
        .help(isPlaying ? "Arrêter ce son" : event?.state.isPaused == true ? "Reprendre ce son" : "Lancer ce son")
    }

    /// Pad Apple Music : un bouton rond lecture / stop, comme un appui sur le pad (stop en fondu de 1 s ; en pause : reprise).
    private func musicButton(_ pad: Pad, event: PlaybackEvent?) -> some View {
        let isPlaying: Bool = if case .playing = event?.state { true } else { false }
        let size = Self.buttonSize(for: density)
        return Button {
            controller.togglePlayStop(at: position)
        } label: {
            (isPlaying ? Icon.stopFill : Icon.playFill).view(size: size * 0.5)
                .frame(width: size, height: size)
                .background(isPlaying ? pad.tint.vividColor : pad.tint.labelColor.opacity(0.18), in: .circle)
                .foregroundStyle(isPlaying ? pad.tint.surfaceColor : pad.tint.labelColor)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .interactiveCursor(.link)
        .help(isPlaying ? "Arrêter le morceau (fondu)" : event?.state.isPaused == true ? "Reprendre le morceau" : "Jouer le morceau dans Apple Music, depuis le début")
        .accessibilityLabel(isPlaying ? "Arrêter" : "Lecture")
    }

    /// Morceau dans le nuage (Internet nécessaire) ou plus dans la bibliothèque de Music.
    @ViewBuilder
    private func musicAvailabilityBadge(_ pad: Pad) -> some View {
        switch pad.music.flatMap({ musicLibrary?.padAvailability[$0.persistentID] }) {
        case .cloud:
            Text("☁")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 5)
                .background(Surface.lightAccent.opacity(0.18), in: .rect(cornerRadius: 6))
                .foregroundStyle(Surface.lightAccent)
                .help("Dans le nuage : Internet nécessaire pour le jouer. Téléchargez-le dans Music avant la représentation.")
                .accessibilityLabel("Dans le nuage")
        case .missing:
            Text("Introuvable")
                .font(.system(size: 9.5, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.red.opacity(0.22), in: .rect(cornerRadius: 6))
                .foregroundStyle(Color(red: 1, green: 0.6, blue: 0.63))
                .help("Ce morceau n'est plus dans la bibliothèque de Music : remplacez-le (glissez-en un autre sur le pad).")
                .accessibilityLabel("Morceau introuvable")
        default:
            EmptyView()
        }
    }

    /// Pad son et lumière : une capsule avec le bouton lecture / stop et l'ampoule (22 pt chacun, 26 sur un grand pad), l'un au-dessus
    /// de l'autre ; sur un pad bas (fenêtre basse), côte à côte, pour que la capsule tienne dans la hauteur du pad.
    @ViewBuilder
    private func mixedCapsule(_ pad: Pad, event: PlaybackEvent?, state: LightState) -> some View {
        let size: CGFloat = density.padHeight >= 74 ? 26 : 22
        let buttons = Group {
            playStopButton(pad, event: event, size: size, inCapsule: true)
            cueButton(pad, state: state, size: size, inCapsule: true)
        }
        Group {
            if density.padHeight >= 54 {
                VStack(spacing: 2) { buttons }
            } else {
                HStack(spacing: 2) { buttons }
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.3), in: .capsule)
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.06)) }
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
                if kind == .mixed {
                    // Colonne son et lumière : deux moitiés. Un son déposé n'importe où fait un pad son ; « + Cue » crée une cue.
                    HStack(spacing: 0) {
                        IconLabel("Son", icon: .plus, size: 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .foregroundStyle(Surface.textTertiary)
                            .accessibilityHidden(true)
                        Rectangle().fill(Surface.emptyPadStroke).frame(width: 1).padding(.vertical, 10)
                        Button {
                            controller.newLightCue(at: position)
                        } label: {
                            IconLabel("Lumière", icon: .plus, size: 12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .foregroundStyle(Surface.lightAccent)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .interactiveCursor(.link)
                        .help("Créer une lumière sur cette case")
                        .accessibilityLabel("Créer une lumière")
                    }
                    .font(.system(size: 11.5))
                } else if kind == .light {
                    // Colonne lumière : un clic crée la lumière (en mode Projecteurs, « Relier » n'existe pas).
                    Button {
                        controller.newLightCue(at: position)
                    } label: {
                        IconLabel("Nouvelle lumière", icon: .plus, size: 13)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Surface.lightAccent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .interactiveCursor(.link)
                    .help("Créer une lumière sur cette case")
                    .accessibilityLabel("Créer une lumière")
                } else {
                    IconLabel(kind == .music ? "Morceau" : kind.hasAudio ? "Déposer un son" : "Nouvelle lumière", icon: .plus, size: 13)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Surface.textTertiary)
                }
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
    /// Des morceaux venus du panneau Apple Music : les cases d'arrivée, numérotées.
    private func updateGroupPreview(_ info: DropInfo) {
        if controller.draggedPosition == nil, controller.musicDragCount > 0, !info.hasItemsConforming(to: [.fileURL]) {
            controller.updateMusicDropPreview(at: position)
            return
        }
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
        controller.clearMusicDropPreview()
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
                    if let tracks = MusicDragToken.parse(text) {
                        controller.endMusicDrag()
                        let placed = controller.dropMusicTracks(tracks, at: target)
                        Self.log.info("Glisser : \(placed) morceau(x) Apple Music déposé(s) sur \(target.description, privacy: .public)")
                        return
                    }
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


/// Les points des projecteurs d'un pad lumière (mode Projecteurs) : c'est le bouton du pad. Un clic allume l'état, un second
/// l'éteint en fondu. **Allumé** : points pleins qui rayonnent, pastille teintée de la couleur du pad, filet clair.
/// **Éteint** : points creux (simples anneaux gris), pastille sombre. La forme change, pas seulement la couleur : l'état se lit
/// sans distinguer les couleurs. Un projecteur éteint dans l'état lui-même est un anneau très sombre.
struct ProjectorToggle: View {
    let summary: LightLookSummary
    let tint: Tint
    let isOn: Bool
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                switch summary.kind {
                case .colors, .alternate:
                    if summary.kind == .alternate { flag("⇄") }
                    ForEach(Array(summary.dots.enumerated()), id: \.offset) { _, dot in point(dot) }
                    if summary.hasStrobe { flag("ϟ") }
                case .program(let number):
                    rainbow
                    flag("P\(number)")
                case .sound:
                    rainbow
                    flag("MIC")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, compact ? 6 : 9)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.5))
                    .overlay { if isOn { RoundedRectangle(cornerRadius: 12).fill(tint.vividColor.opacity(0.22)) } }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isOn ? tint.vividColor.opacity(0.67) : Color.white.opacity(0.08), lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .interactiveCursor(.link)
        .help(isOn ? "Éteindre cette lumière en fondu" : "Allumer cette lumière : \(summary.subtitle)")
        .accessibilityLabel("Lumière")
        .accessibilityValue(isOn ? "Allumée" : "Éteinte")
        .accessibilityHint("Allume ou éteint cette lumière")
    }

    private var size: CGFloat { 10 }

    @ViewBuilder
    private func point(_ dot: LightLookSummary.Dot) -> some View {
        if !dot.isOn {
            Circle().strokeBorder(Color(white: 0.23), lineWidth: 1.5).frame(width: size, height: size)
        } else if isOn {
            Circle()
                .fill(Color(light: dot.color).opacity(0.45 + 0.55 * min(max(dot.intensity, 0), 1)))
                .frame(width: size, height: size)
                .shadow(color: Color(light: dot.color), radius: 3)
        } else {
            Circle().strokeBorder(Surface.textTertiary.opacity(0.8), lineWidth: 1.5).frame(width: size, height: size)
        }
    }

    private var rainbow: some View {
        let gradient = LinearGradient(colors: [.red, .yellow, .green, .blue, .purple], startPoint: .leading, endPoint: .trailing)
        return ZStack {
            if isOn {
                RoundedRectangle(cornerRadius: 4).fill(gradient)
            } else {
                RoundedRectangle(cornerRadius: 4).strokeBorder(Surface.textTertiary.opacity(0.8), lineWidth: 1.5)
            }
        }
        .frame(width: 34, height: 8)
    }

    private func flag(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .bold)).foregroundStyle(Surface.textPrimary).opacity(isOn ? 1 : 0.6)
    }
}

/// À droite du fader d'une colonne lumière en mode Projecteurs (piste C de la maquette) : le **rôle** du fader dans une pastille
/// ambrée (clic ou clic droit = le changer), et, sur la carte **Intensité**, la mini-barre : les 4 projecteurs tels que la barre
/// les montre (fondus compris), un clic en coupe ou rallume un en fondu sans toucher au pad, le bouton **Noir**, et le tempo
/// quand une alternance joue.
struct DMXFaderAccessory: View {
    @Environment(ShowController.self) private var controller
    @Environment(DMXSession.self) private var dmx
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let column: Int
    let role: DMXFaderRole

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
    private static let red = Color(red: 1, green: 0.36, blue: 0.4)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            rolePill
            if role == .general { miniBar }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var rolePill: some View {
        let label = Text(role.title)
            .font(.system(size: 10.5, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Surface.lightAccent.opacity(0.08), in: .capsule)
            .overlay { Capsule().stroke(Surface.lightAccent.opacity(0.35)) }
            .foregroundStyle(role == .none ? Surface.textTertiary : Self.rgb(255, 242, 199))
        return Group {
            if controller.isLocked {
                label
            } else {
                Menu {
                    ForEach(DMXFaderRole.allCases, id: \.self) { choice in
                        Button((choice == role ? "✓ " : "") + choice.title) { controller.setFaderRole(column: column, to: choice) }
                    }
                } label: { label }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .help(controller.isLocked ? "Ce que règle ce fader : \(role.title)" : "Ce que règle ce fader : \(role.title) (cliquer pour le changer)")
    }

    private var miniBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { _ in
                let time = DMXClock.now()
                let colors = dmx.console?.headColors(at: time) ?? []
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 3) {
                        ForEach(0..<(dmx.console?.rig.profile.headCount ?? 4), id: \.self) { index in
                            head(index, rgb: colors.indices.contains(index) ? colors[index] : nil)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .background(Self.rgb(38, 40, 46), in: .rect(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(Self.rgb(58, 61, 69)) }
                    if let info = dmx.console?.alternationInfo(at: time) {
                        HStack(spacing: 4) {
                            Circle().fill(Surface.lightAccent).frame(width: 6, height: 6)
                                .opacity(info.onBeat && !reduceMotion ? 1 : 0.25)
                            Text("⇄ \(Int(info.bpm.rounded())) BPM")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(Surface.textSecondary)
                        }
                        .help("Alternance : tempo du son en cours (sinon tempo de repli)")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Alternance à \(Int(info.bpm.rounded())) battements par minute")
                    }
                }
            }
            Button("Noir") { controller.blackout() }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 20)
                .background(Self.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(Self.red.opacity(0.5), lineWidth: 1) }
                .foregroundStyle(Self.rgb(255, 225, 226))
                .interactiveCursor(.link)
                .help("Éteindre toute la barre en fondu (bouton rond de l'APC)")
        }
    }

    private func head(_ index: Int, rgb: RGB?) -> some View {
        let isOn = dmx.console?.isHeadOn(index) ?? true
        let fill = rgb.map { Color(red: Double($0.red) / 255, green: Double($0.green) / 255, blue: Double($0.blue) / 255) } ?? .clear
        return Button { dmx.toggleHead(index) } label: {
            Circle()
                .fill(Self.rgb(18, 19, 23))
                .overlay { Circle().fill(fill).padding(3) }
                .overlay { Circle().stroke(Self.rgb(74, 77, 85), lineWidth: 1) }
                .frame(width: 16, height: 16)
                .opacity(isOn ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .interactiveCursor(.link)
        .help("Projecteur \(index + 1) : cliquer pour l'allumer ou le couper en fondu (le pad ne change pas)")
        .accessibilityLabel("Projecteur \(index + 1)")
        .accessibilityValue(isOn ? "allumé" : "coupé")
    }
}
