import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Inspecteur (panneau du bas, cadenas ouvert) — solution B de la maquette : deux bandes, au plus
/// `Metrics.inspectorHeight` (≈ 1/5 de la hauteur de la fenêtre).
/// - Bande du haut : transport (lecture, pause, stop, boucle, temps), titre et sous-titre (double-clic pour
///   modifier), nom du fichier d'origine, « Nouvel appui », fondus, couleur (popover), actions du pad.
/// - Bande du bas (pad son) : jauge de volume du pad (dB) et forme d'onde pleine largeur avec élagage.
/// Aucune information n'apparaît deux fois ; les groupes sans rapport sont séparés par un filet.
struct InspectorView: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition

    @State private var waveform: Waveform?

    private static let headerHeight: CGFloat = 52
    private static let waveHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            if let pad = controller.pad(at: position) {
                switch pad.content {
                case .audio(let clip):
                    AudioHeader(position: position, pad: pad, clip: clip, waveform: waveform)
                        .frame(height: Self.headerHeight)
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    HStack(spacing: 10) {
                        TrackGainGauge(name: pad.title, gainDB: clip.gainDB) { controller.setGain(at: position, $0) }
                            .frame(width: 46)
                        WaveformEditor(
                            position: position, clip: clip, tint: pad.tint,
                            event: controller.playback[pad.id], waveform: waveform
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: Self.waveHeight)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .task(id: clip.fileName) { waveform = await controller.waveform(for: clip) }
                case .light:
                    LightHeader(position: position, pad: pad)
                        .frame(height: Self.headerHeight)
                }
            } else {
                emptyCell
                    .frame(height: Self.headerHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: Metrics.inspectorHeight, alignment: .topLeading)
        .background(Surface.panel)
    }

    @ViewBuilder
    private var emptyCell: some View {
        HStack(spacing: 8) {
            Icon.plus.view(size: 15).foregroundStyle(Surface.textTertiary)
            if controller.currentGrid.columns[position.column].kind == .light {
                Text("Ajoutez une commande lumière — LightKey apprend la note de cette case sur le contrôleur.")
            } else {
                Text("Glissez un son de la bibliothèque ou du Finder sur cette case.")
            }
            Spacer(minLength: 8)
            PadActionsMenu(position: position, hasPad: false)
        }
        .font(.system(size: 12))
        .foregroundStyle(Surface.textTertiary)
        .padding(.horizontal, 14)
    }
}

// MARK: - Bande du haut

/// Pad son : transport | titre | (espace) nom du fichier | nouvel appui, fondus | couleur, actions.
private struct AudioHeader: View {
    let position: GridPosition
    let pad: Pad
    let clip: AudioClip
    let waveform: Waveform?

    var body: some View {
        HStack(spacing: 12) {
            TransportControls(position: position, pad: pad, clip: clip, waveform: waveform)
            HeaderDivider()
            TitleFields(position: position, pad: pad)
            Spacer(minLength: 8)
            Text(clip.fileName)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Surface.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 150, alignment: .trailing)
                .layoutPriority(-1)
                .help("Fichier d'origine : \(clip.fileName)")
            HeaderDivider()
            RetriggerControl(position: position, clip: clip)
            FadesButton(position: position, clip: clip)
            HeaderDivider()
            ColorPopoverButton(position: position, pad: pad)
            PadActionsMenu(position: position, hasPad: true)
        }
        .padding(.horizontal, 14)
    }
}

/// Pad lumière : titre | (espace) Tester + note envoyée | couleur, actions.
private struct LightHeader: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad

    var body: some View {
        HStack(spacing: 12) {
            TitleFields(position: position, pad: pad)
            Spacer(minLength: 8)
            Button("Tester", icon: .spotlight, size: 12) { controller.audition(at: position) }
                .buttonStyle(.borderedProminent)
                .tint(Surface.lightAccent)
                .foregroundStyle(Surface.window)
                .controlSize(.small)
                .help("Envoie la note de cette case à LightKey (port « Lalabob Lumière »)")
            Text(noteText)
                .font(.system(size: 11))
                .foregroundStyle(Surface.textSecondary)
                .lineLimit(1)
                .layoutPriority(-1)
            HeaderDivider()
            ColorPopoverButton(position: position, pad: pad)
            PadActionsMenu(position: position, hasPad: true)
        }
        .padding(.horizontal, 14)
    }

    private var noteText: String {
        let label = controller.positionLabel(for: position)
        guard let note = label.components(separatedBy: " · note ").last, label.contains(" · note ") else {
            return "Branchez le contrôleur pour connaître la note envoyée à LightKey."
        }
        let model = controller.connectedControllerName ?? controller.lastControllerModel?.displayName ?? "contrôleur"
        return "LightKey reçoit la note \(note) (\(model))."
    }
}

/// Filet vertical entre deux groupes sans rapport.
private struct HeaderDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 22).accessibilityHidden(true)
    }
}

// MARK: - Titre et sous-titre (double-clic pour modifier)

private struct TitleFields: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad

    @State private var editing: Field?
    @State private var draft = ""
    @FocusState private var focused: Bool

    private enum Field { case title, subtitle }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            editableText(
                pad.title, field: .title, font: .system(size: 13, weight: .bold),
                color: Surface.textPrimary, hint: "Double-cliquer pour renommer"
            )
            editableText(
                pad.subtitle, field: .subtitle, font: .system(size: 11), color: Surface.textSecondary,
                hint: "Double-cliquer pour modifier le sous-titre", placeholder: "Sous-titre"
            )
        }
        .help(controller.positionLabel(for: position))
        .onChange(of: position) { editing = nil }
        .onChange(of: focused) { wasFocused, isFocused in
            if wasFocused, !isFocused { commit() }
        }
    }

    @ViewBuilder
    private func editableText(
        _ text: String, field: Field, font: Font, color: Color, hint: String, placeholder: String = ""
    ) -> some View {
        if editing == field {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(color)
                .focused($focused)
                .frame(minWidth: 60, maxWidth: 200)
                .onSubmit { focused = false }
                .onExitCommand { editing = nil; focused = false }
        } else {
            Text(text.isEmpty ? placeholder : text)
                .font(font)
                .foregroundStyle(text.isEmpty ? Surface.textTertiary : color)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(hint)
                .onTapGesture(count: 2) { start(field) }
        }
    }

    private func start(_ field: Field) {
        draft = field == .title ? pad.title : pad.subtitle
        editing = field
        DispatchQueue.main.async { focused = true }
    }

    private func commit() {
        guard let field = editing else { return }
        switch field {
        case .title:
            let trimmed = draft.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { controller.updatePad(at: position, title: trimmed) }
        case .subtitle:
            controller.updatePad(at: position, subtitle: draft.trimmingCharacters(in: .whitespaces))
        }
        editing = nil
    }
}

// MARK: - Transport

private struct TransportControls: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad
    let clip: AudioClip
    let waveform: Waveform?

    var body: some View {
        let event = controller.playback[pad.id]
        let isPlaying: Bool = if case .playing = event?.state { true } else { false }
        let isPaused = event?.state.isPausedState ?? false
        HStack(spacing: 7) {
            Button {
                controller.audition(at: position)
            } label: {
                (isPlaying ? Icon.restart : Icon.play).view(size: 14)
                    .frame(width: 36, height: 36)
                    .background(pad.tint.vividColor, in: .circle)
                    .foregroundStyle(Surface.window)
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Relancer" : "Lecture")
            .accessibilityLabel(isPlaying ? "Relancer" : "Lecture")

            roundButton(.pause, label: isPaused ? "Reprendre" : "Pause", active: isPaused, tint: Surface.lightAccent) {
                controller.togglePause(at: position)
            }
            .disabled(event == nil)
            roundButton(.stop, label: "Stop", active: false, tint: Surface.textSecondary) {
                controller.stop(at: position)
            }
            .disabled(event == nil)
            roundButton(.loop, label: "Boucle", active: clip.loops, tint: Surface.loopAccent) {
                controller.setLoops(at: position, !clip.loops)
            }

            timeLabel(event)
            if isPaused {
                Text("PAUSE")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(Surface.lightAccent.opacity(0.18), in: .capsule)
                    .foregroundStyle(Surface.lightAccent)
            }
        }
        .fixedSize()
    }

    private func roundButton(
        _ icon: Icon, label: String, active: Bool, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            icon.view(size: 11)
                .frame(width: 28, height: 28)
                .background(active ? tint.opacity(0.18) : Color.white.opacity(0.06), in: .circle)
                .foregroundStyle(active ? tint : Surface.textSecondary)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func timeLabel(_ event: PlaybackEvent?) -> some View {
        let usable = max((clip.trimEnd ?? waveform?.duration ?? 0) - clip.trimStart, 0)
        return TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let elapsed = event?.state.elapsedTime(now: ProcessInfo.processInfo.systemUptime) ?? 0
            let shown = clip.loops && usable > 0 ? elapsed.truncatingRemainder(dividingBy: usable) : min(elapsed, usable)
            Text("\(AudioLibrary.formatDuration(shown)) / \(AudioLibrary.formatDuration(usable))")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Surface.textSecondary)
                .monospacedDigit()
        }
        .accessibilityLabel("Durée utile \(AudioLibrary.formatDuration(usable))")
    }
}

// MARK: - Nouvel appui, fondus

private struct RetriggerControl: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let clip: AudioClip

    var body: some View {
        HStack(spacing: 6) {
            Text("Nouvel appui").font(.system(size: 10)).foregroundStyle(Surface.textTertiary).lineLimit(1)
            Picker(
                "Nouvel appui",
                selection: Binding(get: { clip.retrigger }, set: { controller.setRetrigger(at: position, $0) })
            ) {
                Text("Relancer").tag(RetriggerBehavior.restart)
                Text("Arrêter").tag(RetriggerBehavior.stop)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 140)
            .help("Nouvel appui sur ce pad pendant la lecture : relancer depuis le début, ou arrêter")
        }
        .fixedSize()
    }
}

/// Réglage des fondus d'entrée et de sortie, dans un popover (absents de la maquette B : ajout nécessaire,
/// ces réglages existaient déjà dans l'inspecteur précédent).
private struct FadesButton: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let clip: AudioClip

    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            HStack(spacing: 5) {
                Text("Fondus").font(.system(size: 11, weight: .semibold))
                if clip.fadeIn != nil || clip.fadeOut != nil {
                    Circle().fill(Surface.textSecondary).frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(Surface.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(shown ? Color.white.opacity(0.1) : Color.white.opacity(0.06), in: .rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help("Fondus d'entrée et de sortie")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                fadeRow("Entrée", value: clip.fadeIn) { controller.setFades(at: position, in: $0, out: clip.fadeOut ?? 0) }
                fadeRow("Sortie", value: clip.fadeOut) { controller.setFades(at: position, in: clip.fadeIn ?? 0, out: $0) }
            }
            .padding(12)
            .frame(width: 190)
        }
    }

    /// Interrupteur de fondu + durée (pas de 0,1 s). Activer propose 1 s.
    private func fadeRow(_ title: String, value: TimeInterval?, set: @escaping (TimeInterval) -> Void) -> some View {
        HStack(spacing: 8) {
            Toggle(title, isOn: Binding(get: { value != nil }, set: { set($0 ? 1 : 0) }))
                .toggleStyle(.switch).controlSize(.small)
            if let value {
                Stepper(value: Binding(get: { value }, set: { set(max($0, 0.1)) }), in: 0.1...60, step: 0.1) {
                    Text(AudioLibrary.formatDuration(value)).monospacedDigit()
                }
                .controlSize(.small)
            } else {
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 11))
    }
}

// MARK: - Couleur (popover) : un seul bouton, la teinte en cours

private struct ColorPopoverButton: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad

    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(pad.tint.surfaceColor)
                    .frame(width: 20, height: 20)
                    .overlay { Circle().fill(pad.tint.vividColor).frame(width: 10, height: 10) }
                Text(pad.tint.displayName).font(.system(size: 11, weight: .semibold))
                Chevron()
                    .stroke(Surface.textTertiary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 8, height: 5)
                    .rotationEffect(.degrees(shown ? 180 : 0))
            }
            .foregroundStyle(Surface.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(shown ? Color.white.opacity(0.1) : Color.white.opacity(0.06), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Couleur du pad et intensité de la LED")
        .accessibilityLabel("Couleur du pad : \(pad.tint.displayName)")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 8), spacing: 6) {
                    ForEach(Tint.allCases, id: \.self) { tint in
                        Button {
                            controller.updatePad(at: position, tint: tint)
                        } label: {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(tint.surfaceColor)
                                .frame(width: 24, height: 24)
                                .overlay { Circle().fill(tint.vividColor).frame(width: 8, height: 8) }
                                .overlay {
                                    if tint == pad.tint { RoundedRectangle(cornerRadius: 7).stroke(.white, lineWidth: 2) }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(tint.displayName)
                        .accessibilityLabel(tint.displayName)
                        .accessibilityAddTraits(tint == pad.tint ? .isSelected : [])
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Intensité de la LED").font(.system(size: 10)).foregroundStyle(Surface.textTertiary)
                    Picker(
                        "Intensité LED",
                        selection: Binding(
                            get: { pad.ledIntensity }, set: { controller.updatePad(at: position, ledIntensity: $0) })
                    ) {
                        ForEach(LEDIntensity.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }
            }
            .padding(12)
        }
    }
}

private struct Chevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// MARK: - Actions du pad

/// Couper, copier, coller, dupliquer, vider : regroupés dans un menu (les raccourcis ⌘X/C/V/D/⌫ restent actifs).
private struct PadActionsMenu: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let hasPad: Bool

    var body: some View {
        Menu {
            Button("Couper", icon: .cut) { controller.cutSelection() }.disabled(!hasPad)
            Button("Copier", icon: .copy) { controller.copySelection() }.disabled(!hasPad)
            Button("Coller", icon: .paste) { controller.pasteAtSelection() }.disabled(!controller.canPaste)
            Button("Dupliquer", icon: .duplicate) { controller.duplicateSelection() }.disabled(!hasPad)
            Divider()
            Button("Vider", icon: .trash) { controller.clearSelection() }.disabled(!hasPad)
        } label: {
            Text("Actions").font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Actions sur le pad (\(controller.positionLabel(for: position)))")
    }
}

// MARK: - Volume du pad

/// Jauge verticale du volume propre au pad (−60 dB … +12 dB), indépendante du fader de colonne.
/// Rail, poignée blanche arrondie et valeur en dB, comme les faders de colonne. Le glissement ne modifie le
/// spectacle qu'au relâchement (une seule annulation) ; double-clic : retour à 0 dB.
/// Le nouveau volume s'applique au prochain déclenchement du pad.
private struct TrackGainGauge: View {
    let name: String
    let gainDB: Double
    let onCommit: (Double) -> Void

    @State private var draggedDB: Double?

    private let handleHeight: CGFloat = 8
    private var shownDB: Double { draggedDB ?? gainDB }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let travel = max(geometry.size.height - handleHeight, 1)
                let position = Gain.gaugePosition(forDB: shownDB)
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(width: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 26, height: handleHeight)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .offset(y: -CGFloat(position) * travel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { draggedDB = decibels(at: $0.location.y, travel: travel) }
                        .onEnded { value in
                            draggedDB = nil
                            onCommit(decibels(at: value.location.y, travel: travel))
                        }
                )
                .onTapGesture(count: 2) { onCommit(0) }
            }
            Text(Gain.formatDecibels(db: shownDB))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Surface.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 6)
        .background(Surface.well, in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.05)) }
        .help("Volume de ce pad (indépendant du fader de colonne) — double-clic : 0 dB. Appliqué au prochain déclenchement.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume du pad \(name)")
        .accessibilityValue(Gain.formatDecibels(db: shownDB))
        .accessibilityAdjustableAction { direction in
            onCommit(shownDB + (direction == .increment ? 1 : -1))
        }
    }

    /// Gain correspondant à une ordonnée dans la jauge (poignée de `handleHeight`, haut = +12 dB).
    private func decibels(at y: CGFloat, travel: CGFloat) -> Double {
        Gain.decibels(forGaugePosition: 1 - Double((y - handleHeight / 2) / travel))
    }
}
