import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Inspecteur (panneau du bas, cadenas ouvert) : une barre compacte, au plus `Metrics.inspectorHeight`
/// (≈ 1/5 de la hauteur de la fenêtre). Le titre et le sous-titre se modifient en double-cliquant
/// dessus, dans l'en-tête : il n'y a pas de champs séparés qui dupliqueraient cette information.
/// Pad son : transport, forme d'onde avec élagage et fondus. Pad lumière : bouton Tester.
struct InspectorView: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition

    @State private var waveform: Waveform?

    var body: some View {
        let pad = controller.pad(at: position)
        VStack(alignment: .leading, spacing: 6) {
            InspectorHeader(position: position, pad: pad)
            if let pad {
                switch pad.content {
                case .audio(let clip):
                    HStack(alignment: .center, spacing: 14) {
                        TransportPanel(position: position, pad: pad, clip: clip, waveform: waveform)
                            .frame(width: 190)
                        WaveformEditor(
                            position: position, clip: clip, tint: pad.tint,
                            event: controller.playback[pad.id], waveform: waveform
                        )
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 60, maxHeight: 64)
                        AppearancePanel(position: position, pad: pad)
                            .frame(width: 176)
                    }
                    .task(id: clip.fileName) { waveform = await controller.waveform(for: clip) }
                case .light:
                    HStack(alignment: .center, spacing: 14) {
                        LightPanel(position: position)
                        Spacer(minLength: 0)
                        AppearancePanel(position: position, pad: pad)
                            .frame(width: 176)
                    }
                }
            } else {
                emptyCell
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
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
        }
        .font(.system(size: 12))
        .foregroundStyle(Surface.textTertiary)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - En-tête : icône, titre/sous-titre éditables, position, actions

private struct InspectorHeader: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad?

    @State private var editing: Field?
    @State private var draft = ""
    @FocusState private var focused: Bool

    private enum Field { case title, subtitle }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(pad?.tint.vividColor ?? Surface.textTertiary)
                .frame(width: 10, height: 10)

            editableText(
                pad?.title ?? "Case vide", field: .title, font: .system(size: 13, weight: .semibold),
                color: Surface.textPrimary, hint: "Double-cliquer pour renommer"
            )
            if pad != nil {
                editableText(
                    pad?.subtitle ?? "", field: .subtitle, font: .system(size: 11), color: Surface.textSecondary,
                    hint: "Double-cliquer pour modifier le sous-titre", placeholder: "Sous-titre"
                )
            }

            Text(controller.positionLabel(for: position))
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: 0x9EA2AC))
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 6))
                .lineLimit(1)
                .layoutPriority(-1)

            Spacer(minLength: 4)

            Group {
                Button("Couper", icon: .cut) { controller.cutSelection() }.disabled(pad == nil)
                Button("Copier", icon: .copy) { controller.copySelection() }.disabled(pad == nil)
                Button("Coller", icon: .paste) { controller.pasteAtSelection() }.disabled(!controller.canPaste)
                Button("Dupliquer", icon: .duplicate) { controller.duplicateSelection() }.disabled(pad == nil)
                Button("Vider", icon: .trash) { controller.clearSelection() }.disabled(pad == nil)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .frame(height: 26)
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
                .fixedSize()
                .onSubmit { focused = false }
                .onExitCommand { editing = nil; focused = false }
        } else {
            Text(text.isEmpty ? placeholder : text)
                .font(font)
                .foregroundStyle(text.isEmpty ? Surface.textTertiary : color)
                .lineLimit(1)
                .help(pad == nil ? "" : hint)
                .onTapGesture(count: 2) { start(field) }
        }
    }

    private func start(_ field: Field) {
        guard let pad else { return }
        draft = field == .title ? pad.title : pad.subtitle
        editing = field
        DispatchQueue.main.async { focused = true }
    }

    private func commit() {
        guard let field = editing, pad != nil else { return }
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

// MARK: - Transport et réglages du son

private struct TransportPanel: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad
    let clip: AudioClip
    let waveform: Waveform?

    var body: some View {
        let event = controller.playback[pad.id]
        let isPlaying: Bool = if case .playing = event?.state { true } else { false }
        let isPaused = event?.state.isPausedState ?? false
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    controller.audition(at: position)
                } label: {
                    (isPlaying ? Icon.restart : Icon.play).view(size: 14)
                        .frame(width: 32, height: 32)
                        .background(pad.tint.vividColor, in: .circle)
                        .foregroundStyle(Surface.window)
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "Relancer" : "Lecture")
                .accessibilityLabel(isPlaying ? "Relancer" : "Lecture")

                Button(isPaused ? "Reprendre" : "Pause", icon: .pause) { controller.togglePause(at: position) }
                    .labelStyle(.iconOnly).controlSize(.small).disabled(event == nil)
                Button("Stop", icon: .stop) { controller.stop(at: position) }
                    .labelStyle(.iconOnly).controlSize(.small).disabled(event == nil)

                timeLabel(event)
                if isPaused {
                    Text("Pause").font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Surface.lightAccent.opacity(0.2), in: .capsule)
                        .foregroundStyle(Surface.lightAccent)
                }
            }

            Text(clip.fileName).font(.system(size: 10.5)).foregroundStyle(Surface.textTertiary).lineLimit(1)

            fadeRow("Entrée", value: clip.fadeIn) { controller.setFades(at: position, in: $0, out: clip.fadeOut ?? 0) }
            fadeRow("Sortie", value: clip.fadeOut) { controller.setFades(at: position, in: clip.fadeIn ?? 0, out: $0) }
            Toggle("Boucle", isOn: Binding(get: { clip.loops }, set: { controller.setLoops(at: position, $0) }))
                .toggleStyle(.switch).controlSize(.mini)
                .font(.system(size: 10.5))
                .foregroundStyle(Surface.textSecondary)

            Picker(
                "Nouvel appui",
                selection: Binding(get: { clip.retrigger }, set: { controller.setRetrigger(at: position, $0) })
            ) {
                Text("Relancer").tag(RetriggerBehavior.restart)
                Text("Arrêter").tag(RetriggerBehavior.stop)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .help("Nouvel appui sur ce pad : relancer depuis le début, ou arrêter")
        }
    }

    private func timeLabel(_ event: PlaybackEvent?) -> some View {
        let usable = max((clip.trimEnd ?? waveform?.duration ?? 0) - clip.trimStart, 0)
        return TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let elapsed = event?.state.elapsedTime(now: ProcessInfo.processInfo.systemUptime) ?? 0
            let shown = clip.loops && usable > 0 ? elapsed.truncatingRemainder(dividingBy: usable) : min(elapsed, usable)
            Text("\(AudioLibrary.formatDuration(shown)) / \(AudioLibrary.formatDuration(usable))")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Surface.textSecondary)
                .monospacedDigit()
        }
        .accessibilityLabel("Durée utile \(AudioLibrary.formatDuration(usable))")
    }

    /// Interrupteur de fondu + durée, en une ligne compacte (pas de 0,1 s). Activer propose 1 s.
    private func fadeRow(_ title: String, value: TimeInterval?, set: @escaping (TimeInterval) -> Void) -> some View {
        HStack(spacing: 6) {
            Toggle(title, isOn: Binding(get: { value != nil }, set: { set($0 ? 1 : 0) }))
                .toggleStyle(.switch).controlSize(.mini)
            if let value {
                Stepper(value: Binding(get: { value }, set: { set(max($0, 0.1)) }), in: 0.1...60, step: 0.1) {
                    Text(AudioLibrary.formatDuration(value)).monospacedDigit()
                }
                .controlSize(.mini)
            } else {
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(Surface.textSecondary)
    }
}

// MARK: - Pad lumière

private struct LightPanel: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition

    var body: some View {
        HStack(spacing: 10) {
            Button("Tester", icon: .spotlight, size: 12) { controller.audition(at: position) }
                .buttonStyle(.borderedProminent)
                .tint(Surface.lightAccent)
                .foregroundStyle(Surface.window)
                .controlSize(.small)
                .help("Envoie la note de cette case à LightKey (port « Lalabob Lumière »)")
            Text(noteText)
                .font(.system(size: 11))
                .foregroundStyle(Surface.textSecondary)
                .lineLimit(2)
        }
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

// MARK: - Couleur et intensité (tous les pads)

private struct AppearancePanel: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 4), count: 8), spacing: 4) {
                ForEach(Tint.allCases, id: \.self) { tint in
                    Button {
                        controller.updatePad(at: position, tint: tint)
                    } label: {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(tint.surfaceColor)
                            .frame(width: 18, height: 18)
                            .overlay {
                                if tint == pad.tint { RoundedRectangle(cornerRadius: 5).stroke(.white, lineWidth: 2) }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(tint.displayName)
                    .accessibilityLabel(tint.displayName)
                    .accessibilityAddTraits(tint == pad.tint ? .isSelected : [])
                }
            }
            Picker(
                "Intensité LED",
                selection: Binding(get: { pad.ledIntensity }, set: { controller.updatePad(at: position, ledIntensity: $0) })
            ) {
                ForEach(LEDIntensity.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
        }
    }
}
