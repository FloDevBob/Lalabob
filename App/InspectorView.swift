import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Inspecteur (panneau du bas, cadenas ouvert).
/// Pad son : transport, forme d'onde avec élagage et fondus, réglages, apparence.
/// Pad lumière : bouton Tester, note reçue par LightKey, apparence.
struct InspectorView: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition

    @State private var waveform: Waveform?

    var body: some View {
        let pad = controller.pad(at: position)
        VStack(alignment: .leading, spacing: 14) {
            header(pad)
            if let pad {
                switch pad.content {
                case .audio(let clip):
                    HStack(alignment: .top, spacing: 20) {
                        TransportPanel(position: position, pad: pad, clip: clip, waveform: waveform)
                            .frame(width: 300)
                        WaveformEditor(
                            position: position, clip: clip, tint: pad.tint,
                            event: controller.playback[pad.id], waveform: waveform
                        )
                        .frame(minHeight: 120)
                    }
                    .task(id: clip.fileName) { waveform = await controller.waveform(for: clip) }
                case .light:
                    LightPanel(position: position)
                }
                AppearancePanel(position: position, pad: pad)
            } else {
                emptyCell
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Surface.panel)
    }

    private func header(_ pad: Pad?) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(pad?.tint.vividColor ?? Surface.textTertiary)
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(pad?.title ?? "Case vide")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Surface.textPrimary)
                    if let subtitle = pad?.subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(Surface.textSecondary)
                    }
                }
                Text(controller.positionLabel(for: position))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Surface.textTertiary)
            }
            Spacer()
            Group {
                Button("Couper", icon: .cut) { controller.cutSelection() }
                    .disabled(pad == nil)
                Button("Copier", icon: .copy) { controller.copySelection() }
                    .disabled(pad == nil)
                Button("Coller", icon: .paste) { controller.pasteAtSelection() }
                    .disabled(!controller.canPaste)
                Button("Dupliquer", icon: .duplicate) { controller.duplicateSelection() }
                    .disabled(pad == nil)
                Button("Vider", icon: .trash) { controller.clearSelection() }
                    .disabled(pad == nil)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Couper, copier, coller, dupliquer, vider")
        }
    }

    @ViewBuilder
    private var emptyCell: some View {
        if controller.currentGrid.columns[position.column].kind == .light {
            Button("Nouvelle cue", icon: .plus) { controller.newLightCue(at: position) }
            Text("LightKey reçoit la note de cette case : réglez son mapping MIDI sur le contrôleur.")
                .font(.system(size: 11.5))
                .foregroundStyle(Surface.textTertiary)
        } else {
            Text("Glissez un son de la bibliothèque ou du Finder sur cette case.")
                .font(.system(size: 12))
                .foregroundStyle(Surface.textTertiary)
        }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    controller.audition(at: position)
                } label: {
                    (isPlaying ? Icon.restart : Icon.play).view(size: 22)
                        .frame(width: 52, height: 52)
                        .background(pad.tint.vividColor, in: .circle)
                        .foregroundStyle(Surface.window)
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "Relancer" : "Lecture")
                .accessibilityLabel(isPlaying ? "Relancer" : "Lecture")

                Button(isPaused ? "Reprendre" : "Pause", icon: .pause) { controller.togglePause(at: position) }
                    .labelStyle(.iconOnly)
                    .disabled(event == nil)
                Button("Stop", icon: .stop) { controller.stop(at: position) }
                    .labelStyle(.iconOnly)
                    .disabled(event == nil)

                VStack(alignment: .leading, spacing: 2) {
                    timeLabel(event)
                    if isPaused {
                        Text("En pause")
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Surface.lightAccent.opacity(0.2), in: .capsule)
                            .foregroundStyle(Surface.lightAccent)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(clip.fileName).font(.system(size: 12)).foregroundStyle(Surface.textPrimary).lineLimit(1)
                Text(controller.fileDescription(for: clip) ?? "Fichier introuvable")
                    .font(Typography.mono)
                    .foregroundStyle(Surface.textTertiary)
            }

            fadeRow("Fondu entrée", value: clip.fadeIn) { controller.setFades(at: position, in: $0, out: clip.fadeOut ?? 0) }
            fadeRow("Fondu sortie", value: clip.fadeOut) { controller.setFades(at: position, in: clip.fadeIn ?? 0, out: $0) }
            Toggle("Boucle", isOn: Binding(get: { clip.loops }, set: { controller.setLoops(at: position, $0) }))
                .toggleStyle(.switch)
                .controlSize(.small)

            HStack {
                Text("Nouvel appui").font(.system(size: 12)).foregroundStyle(Surface.textSecondary)
                Picker(
                    "Nouvel appui",
                    selection: Binding(get: { clip.retrigger }, set: { controller.setRetrigger(at: position, $0) })
                ) {
                    Text("Relancer").tag(RetriggerBehavior.restart)
                    Text("Arrêter").tag(RetriggerBehavior.stop)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private func timeLabel(_ event: PlaybackEvent?) -> some View {
        let usable = max((clip.trimEnd ?? waveform?.duration ?? 0) - clip.trimStart, 0)
        return TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let elapsed = event?.state.elapsedTime(now: ProcessInfo.processInfo.systemUptime) ?? 0
            let shown = clip.loops && usable > 0 ? elapsed.truncatingRemainder(dividingBy: usable) : min(elapsed, usable)
            Text("\(AudioLibrary.formatDuration(shown)) / \(AudioLibrary.formatDuration(usable))")
                .font(Typography.mono)
                .foregroundStyle(Surface.textSecondary)
                .monospacedDigit()
        }
        .accessibilityLabel("Durée utile \(AudioLibrary.formatDuration(usable))")
    }

    /// Interrupteur de fondu + durée (pas de 0,1 s). Activer propose 1 s.
    private func fadeRow(_ title: String, value: TimeInterval?, set: @escaping (TimeInterval) -> Void) -> some View {
        HStack {
            Toggle(title, isOn: Binding(get: { value != nil }, set: { set($0 ? 1 : 0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
            Spacer()
            if let value {
                Stepper(value: Binding(get: { value }, set: { set(max($0, 0.1)) }), in: 0.1...60, step: 0.1) {
                    Text(value.formatted(.number.precision(.fractionLength(1))) + " s")
                        .font(Typography.mono)
                        .foregroundStyle(Surface.textSecondary)
                }
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Pad lumière

private struct LightPanel: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition

    var body: some View {
        HStack(spacing: 14) {
            Button("Tester", icon: .spotlight) { controller.audition(at: position) }
                .buttonStyle(.borderedProminent)
                .tint(Surface.lightAccent)
                .foregroundStyle(Surface.window)
                .help("Envoie la note de cette case à LightKey (port « Lalabob Lumière »)")
            Text(noteText)
                .font(.system(size: 12))
                .foregroundStyle(Surface.textSecondary)
        }
    }

    private var noteText: String {
        let label = controller.positionLabel(for: position)
        guard let note = label.components(separatedBy: " · note ").last, label.contains(" · note ") else {
            return "Branchez le contrôleur une fois pour connaître la note envoyée à LightKey."
        }
        let model = controller.connectedControllerName ?? controller.lastControllerModel?.displayName ?? "contrôleur"
        return "LightKey reçoit la note \(note) (\(model)), sur le contrôleur et sur « Lalabob Lumière »."
    }
}

// MARK: - Apparence (tous les pads)

private struct AppearancePanel: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad

    @State private var title = ""
    @State private var subtitle = ""
    @FocusState private var focusedField: Field?

    private enum Field { case title, subtitle }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            texts.frame(width: 300)
            colors
            intensity
            Spacer(minLength: 0)
        }
        .onAppear { load(pad) }
        .onChange(of: position) { load(controller.pad(at: position)) }
        .onChange(of: pad) { if focusedField == nil { load(pad) } }
        .onChange(of: focusedField) { old, _ in
            if old == .title { commitTitle() }
            if old == .subtitle { commitSubtitle() }
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Titre").font(.system(size: 11)).foregroundStyle(Surface.textTertiary)
            TextField("Titre", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .title)
                .onSubmit(commitTitle)
            Text("Sous-titre").font(.system(size: 11)).foregroundStyle(Surface.textTertiary)
            TextField("Sous-titre", text: $subtitle)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .subtitle)
                .onSubmit(commitSubtitle)
        }
    }

    private var colors: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couleur du pad").font(.system(size: 11)).foregroundStyle(Surface.textTertiary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8), spacing: 6) {
                ForEach(Tint.allCases, id: \.self) { tint in
                    Button {
                        controller.updatePad(at: position, tint: tint)
                    } label: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tint.surfaceColor)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().fill(tint.vividColor).frame(width: 10, height: 10))
                            .overlay {
                                if tint == pad.tint { RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 2) }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(tint.displayName)
                    .accessibilityLabel(tint.displayName)
                    .accessibilityAddTraits(tint == pad.tint ? .isSelected : [])
                }
            }
        }
    }

    private var intensity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Intensité LED").font(.system(size: 11)).foregroundStyle(Surface.textTertiary)
            Picker(
                "Intensité LED",
                selection: Binding(get: { pad.ledIntensity }, set: { controller.updatePad(at: position, ledIntensity: $0) })
            ) {
                ForEach(LEDIntensity.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
        }
    }

    private func load(_ pad: Pad?) {
        title = pad?.title ?? ""
        subtitle = pad?.subtitle ?? ""
    }

    private func commitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            load(controller.pad(at: position))  // un titre vide n'est pas accepté
            return
        }
        controller.updatePad(at: position, title: trimmed)
    }

    private func commitSubtitle() {
        controller.updatePad(at: position, subtitle: subtitle.trimmingCharacters(in: .whitespaces))
    }
}
