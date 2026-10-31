import AVFoundation
import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Inspecteur (panneau du bas, cadenas ouvert) : une barre de hauteur fixe `Metrics.inspectorHeight`
/// (≈ 1/5 de la fenêtre), pour qu'elle ne saute pas d'un pad à l'autre.
/// Pad son : une barre de commandes (lecture, pause, stop, boucle), puis la forme d'onde qui prend toute
/// la hauteur restante — l'élagage et les fondus se règlent directement sur elle. Couleur à droite.
/// Le titre et le sous-titre se modifient en double-cliquant dans l'en-tête.
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
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 6) {
                            TransportBar(position: position, pad: pad, clip: clip, waveform: waveform)
                            WaveformEditor(
                                position: position, clip: clip, tint: pad.tint,
                                event: controller.playback[pad.id], waveform: waveform
                            )
                            .frame(maxHeight: .infinity)
                        }
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
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.inspectorHeight, alignment: .topLeading)
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

// MARK: - Barre de commandes : lecture, pause, stop et boucle ensemble

private struct TransportBar: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad
    let clip: AudioClip
    let waveform: Waveform?

    var body: some View {
        let event = controller.playback[pad.id]
        let isPlaying: Bool = if case .playing = event?.state { true } else { false }
        let isPaused = event?.state.isPausedState ?? false
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Button {
                    controller.audition(at: position)
                } label: {
                    (isPlaying ? Icon.restart : Icon.play).view(size: 13)
                        .frame(width: 28, height: 28)
                        .background(pad.tint.vividColor, in: .circle)
                        .foregroundStyle(Surface.window)
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "Relancer" : "Lecture")
                .accessibilityLabel(isPlaying ? "Relancer" : "Lecture")

                transportButton(isPaused ? "Reprendre" : "Pause", icon: .pause, enabled: event != nil) {
                    controller.togglePause(at: position)
                }
                transportButton("Stop", icon: .stop, enabled: event != nil) { controller.stop(at: position) }

                Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 16).padding(.horizontal, 2)

                loopButton
            }
            .padding(.horizontal, 5)
            .frame(height: 34)
            .background(Surface.well, in: .capsule)

            timeLabel(event)
            if isPaused {
                Text("Pause").font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Surface.lightAccent.opacity(0.2), in: .capsule)
                    .foregroundStyle(Surface.lightAccent)
            }

            Spacer(minLength: 8)

            Text(clip.fileName)
                .font(.system(size: 10.5))
                .foregroundStyle(Surface.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)

            retriggerMenu
        }
    }

    private func transportButton(_ title: String, icon: Icon, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon.view(size: 13)
                .frame(width: 26, height: 26)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Surface.textPrimary : Surface.textTertiary.opacity(0.5))
        .disabled(!enabled)
        .help(title)
        .accessibilityLabel(title)
    }

    /// Boucle : un bouton à bascule, allumé quand le son boucle.
    private var loopButton: some View {
        Button {
            controller.setLoops(at: position, !clip.loops)
        } label: {
            Icon.loop.view(size: 14)
                .frame(width: 28, height: 26)
                .background(clip.loops ? pad.tint.vividColor.opacity(0.28) : .clear, in: .capsule)
                .foregroundStyle(clip.loops ? pad.tint.vividColor : Surface.textSecondary)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(clip.loops ? "Boucle activée" : "Boucle désactivée")
        .accessibilityLabel("Boucle")
        .accessibilityValue(clip.loops ? "activée" : "désactivée")
        .accessibilityAddTraits(.isToggle)
    }

    /// Nouvel appui sur un pad qui joue déjà : relancer ou arrêter.
    private var retriggerMenu: some View {
        Menu {
            Picker(
                "Nouvel appui",
                selection: Binding(get: { clip.retrigger }, set: { controller.setRetrigger(at: position, $0) })
            ) {
                Text("Relancer depuis le début").tag(RetriggerBehavior.restart)
                Text("Arrêter le son").tag(RetriggerBehavior.stop)
            }
            .pickerStyle(.inline)
        } label: {
            Text(clip.retrigger == .restart ? "Appui : relancer" : "Appui : arrêter")
                .font(.system(size: 10.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Nouvel appui sur ce pad pendant qu'il joue")
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

// MARK: - Aperçu (Xcode) : un pad avec un son de synthèse, des fondus et un élagage

#Preview("Inspecteur — pad son") {
    Fonts.register()
    let directory = FileManager.default.temporaryDirectory.appending(path: "lalabob-preview-audio", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000 * 6),
        let samples = buffer.floatChannelData,
        let file = try? AVAudioFile(forWriting: directory.appending(path: "essai.wav"), settings: format.settings)
    {
        buffer.frameLength = buffer.frameCapacity
        for i in 0..<Int(buffer.frameLength) {
            let t = Float(i) / 8000
            samples[0][i] = sin(t * 440) * (0.2 + 0.7 * abs(sin(t * 1.3))) * (t < 0.3 ? 0.2 : 1)
        }
        try? file.write(from: buffer)
    }
    var grid = PadGrid.empty(name: "Essai")
    let position = GridPosition(column: 1, row: 2)
    grid[position] = Pad(
        title: "Orage lointain", subtitle: "Ambiance", tint: .azur,
        content: .audio(clip: AudioClip(fileName: "essai.wav", trimStart: 0.4, trimEnd: 5.2, fadeIn: 0.8, fadeOut: 1.4, loops: true)))
    let controller = ShowController(show: Show(name: "Essai", grids: [grid]), audioDirectory: directory)
    controller.selection = position
    return InspectorView(position: position)
        .environment(controller)
        .frame(width: 1100)
        .preferredColorScheme(.dark)
}
