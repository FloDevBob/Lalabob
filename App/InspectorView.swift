import AVFoundation
import AppKit
import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Inspecteur (panneau du bas, cadenas ouvert) — solution B de la maquette : deux bandes, au plus
/// `Metrics.inspectorHeight` (≈ 1/5 de la hauteur de la fenêtre).
/// - Bande du haut : transport (lecture, pause, stop et boucle groupés, temps), titre et sous-titre (double-clic
///   pour modifier), nom du fichier d'origine, « Nouvel appui », couleur (popover), actions du pad.
/// - Bande du bas (pad son) : jauge de volume du pad (dB) et forme d'onde pleine largeur avec élagage ;
///   les fondus se règlent sur l'onde (puces sous la courbe, poignée de durée).
/// Aucune information n'apparaît deux fois ; les groupes sans rapport sont séparés par un filet.
/// Case vide : l'écran de repos (`IdleBar`). Pad lumière : son en-tête, puis les indicateurs et l'astuce (`IdleContent`).
/// Verrouillé, une version allégée du même panneau reste affichée pour le son lancé : lecture, pause, stop, tête de
/// lecture, volume du pad et fondus se règlent (réglages de jeu) ; couleur, actions, textes, boucle, « Nouvel appui »
/// et élagage ne se modifient pas.
struct InspectorView: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition

    @State private var waveform: Waveform?

    private static let headerHeight: CGFloat = 52
    private static let waveHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            if let pad = controller.pad(at: position) {
                // Fiche 07 : un pad son et lumière aura sa propre disposition ; pour l'instant le son prime.
                if let clip = pad.audio {
                    AudioHeader(position: position, pad: pad, clip: clip, waveform: waveform)
                        .frame(height: Self.headerHeight)
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    HStack(spacing: 10) {
                        TrackGainGauge(
                            name: pad.title, gainDB: clip.gainDB,
                            onLive: { controller.previewGain(at: position, $0) },
                            onCommit: { controller.setGain(at: position, $0) })
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
                } else if let track = pad.music {
                    MusicHeader(position: position, pad: pad, track: track)
                        .frame(height: Self.headerHeight)
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    MusicDetails(position: position, pad: pad, track: track)
                } else {
                    LightHeader(position: position, pad: pad)
                        .frame(height: Self.headerHeight)
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    IdleContent()
                }
            } else {
                IdleBar(emptyPosition: position)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.inspectorHeight, alignment: .topLeading)
        .background(Surface.panel)
    }
}

// MARK: - Bande du haut

/// Pad son : transport | titre | (espace) nom du fichier | nouvel appui | couleur, actions.
private struct AudioHeader: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad
    let clip: AudioClip
    let waveform: Waveform?

    /// Pad son et lumière : la bande du haut est plus dense (groupe Lumière, type du pad) ; le nom du fichier est abrégé d'abord.
    private var isMixed: Bool { pad.light != nil }

    var body: some View {
        HStack(spacing: isMixed ? 8 : 12) {
            TransportControls(position: position, pad: pad, clip: clip, waveform: waveform)
            HeaderDivider()
            TitleFields(position: position, pad: pad)
            if isMixed { LightGroup(position: position, pad: pad) }
            Spacer(minLength: 8)
            Text(clip.fileName)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Surface.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: isMixed ? 100 : 150, alignment: .trailing)
                .layoutPriority(-2)
                .help("Fichier d'origine : \(clip.fileName)")
            if controller.isLocked {
                HeaderDivider()
                TintSwatch(tint: pad.tint)
            } else {
                HeaderDivider()
                if isMixed {
                    MixedRetriggerMenu(position: position, pad: pad, clip: clip)
                } else {
                    RetriggerControl(position: position, clip: clip)
                }
                PadKindControl(position: position, pad: pad)
                HeaderDivider()
                ColorPopoverButton(position: position, pad: pad)
                PadActionsMenu(position: position, hasPad: true)
            }
        }
        .padding(.horizontal, 14)
    }
}

/// Pastille de la teinte, sans action (panneau verrouillé).
private struct TintSwatch: View {
    let tint: Tint

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(tint.surfaceColor)
            .frame(width: 20, height: 20)
            .overlay { Circle().fill(tint.vividColor).frame(width: 10, height: 10) }
            .accessibilityLabel("Couleur du pad : \(tint.displayName)")
    }
}

/// Pad lumière : titre | (espace) Tester + note envoyée | couleur, actions.
/// Pad Apple Music : lecture / pause et stop, temps, titre et sous-titre, morceau d'origine, couleur et actions.
private struct MusicHeader: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad
    let track: MusicTrackRef

    var body: some View {
        let event = controller.playback[pad.id]
        let isPlaying: Bool = if case .playing = event?.state { true } else { false }
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Button {
                    controller.togglePlayStop(at: position)
                } label: {
                    (isPlaying ? Icon.pauseFill : Icon.playFill).view(size: 15)
                        .frame(width: 36, height: 36)
                        .background(pad.tint.vividColor, in: .circle)
                        .foregroundStyle(pad.tint.surfaceColor)
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "Pause (Espace)" : "Jouer dans Apple Music (Espace)")
                .accessibilityLabel(isPlaying ? "Pause" : "Lecture")
                Button {
                    controller.stop(at: position)
                } label: {
                    Icon.stopFill.view(size: 13)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08), in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(event == nil)
                .help("Arrêter en fondu")
                .accessibilityLabel("Arrêter")
            }
            .padding(4)
            .background(Color.black.opacity(0.3), in: .capsule)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.06)))
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                Text("\(AudioLibrary.formatDuration(MusicDetails.elapsed(event))) / \(AudioLibrary.formatDuration(track.duration))")
                    .font(Typography.mono)
                    .foregroundStyle(Surface.textSecondary)
            }
            HeaderDivider()
            TitleFields(position: position, pad: pad)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text([track.title, track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                    .lineLimit(1).truncationMode(.middle)
                if let playlist = track.playlistName {
                    Text("Playlist « \(playlist) »").lineLimit(1)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Surface.textTertiary)
            .layoutPriority(-1)
            if !controller.isLocked {
                HeaderDivider()
                ColorPopoverButton(position: position, pad: pad)
                PadActionsMenu(position: position, hasPad: true)
            }
        }
        .padding(.horizontal, 14)
    }
}

/// Bande du bas d'un pad Apple Music : pochette, barre de position (cliquer ou glisser pour aller à un moment du morceau),
/// et ce qui n'existe pas pour un morceau protégé.
private struct MusicDetails: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad
    let track: MusicTrackRef

    static func elapsed(_ event: PlaybackEvent?) -> TimeInterval {
        switch event?.state {
        case .playing(let startedAt): max(0, ProcessInfo.processInfo.systemUptime - startedAt)
        case .paused(let elapsed): elapsed
        default: 0
        }
    }

    var body: some View {
        let event = controller.playback[pad.id]
        HStack(alignment: .center, spacing: 16) {
            RoundedRectangle(cornerRadius: 10)
                .fill(pad.tint.surfaceColor)
                .overlay { Icon.music.view(size: 34).foregroundStyle(pad.tint.labelColor.opacity(0.8)) }
                .frame(width: 116, height: 116)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                .accessibilityLabel("Pochette de \(track.album.isEmpty ? track.title : track.album)")
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { proxy in
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        let fraction = track.duration > 0 ? min(1, Self.elapsed(event) / track.duration) : 0
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 10).fill(Surface.well)
                            Rectangle().fill(pad.tint.vividColor.opacity(0.25)).frame(width: proxy.size.width * fraction)
                            Rectangle().fill(.white).frame(width: 2).padding(.vertical, 4).offset(x: proxy.size.width * fraction - 1)
                            if event == nil {
                                Text("Jouez le morceau, puis cliquez pour aller à un moment précis")
                                    .font(.system(size: 11)).foregroundStyle(Surface.textTertiary).padding(.leading, 10)
                            }
                        }
                        .clipShape(.rect(cornerRadius: 10))
                    }
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                        guard proxy.size.width > 0, track.duration > 0 else { return }
                        controller.seekMusic(at: position, to: max(0, min(1, value.location.x / proxy.size.width)) * track.duration)
                    })
                }
                .frame(height: 34)
                .interactiveCursor(.link, enabled: event != nil)
                .accessibilityElement()
                .accessibilityLabel("Position dans le morceau")
                .accessibilityValue("\(AudioLibrary.formatDuration(Self.elapsed(event))) sur \(AudioLibrary.formatDuration(track.duration))")
                IconLabel("Fondus, élagage et volume du pad : non disponibles pour un morceau Apple Music. Volume général : 9e fader.", icon: .warning, size: 13)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Surface.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

private struct LightHeader: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad

    var body: some View {
        HStack(spacing: 12) {
            TitleFields(position: position, pad: pad)
            Spacer(minLength: 8)
            Button("Tester", icon: .spotlight, size: 12) { controller.testCue(at: position) }
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
            if pad.awaitsSound {
                Text("En attente de son : déposez un fichier sur le pad")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Surface.lightAccent)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            HeaderDivider()
            PadKindControl(position: position, pad: pad)
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

/// Pad son et lumière : le groupe « Lumière » de la bande du haut — ampoule (à la couleur du pad quand la cue est allumée dans
/// LightKey), note envoyée, appairage, et « Tester » (la cue seule, sans le son).
private struct LightGroup: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad

    var body: some View {
        let state = controller.lightState(at: position)
        let paired = pad.light?.isPaired == true
        HStack(spacing: 8) {
            Icon.lightbulbFill.view(size: 14)
                .foregroundStyle(state == .on ? pad.tint.vividColor : Surface.lightAccent.opacity(state == .off ? 0.5 : 1))
                .accessibilityHidden(true)
            Text(noteText + (paired ? " ✓" : ""))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(paired ? Surface.textPrimary : Surface.textSecondary)
                .lineLimit(1)
            Button("Tester") { controller.testCue(at: position) }
                .controlSize(.small)
                .help("Envoie la cue à LightKey, sans lancer le son")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Surface.lightAccent.opacity(0.07), in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Surface.lightAccent.opacity(0.25)) }
        .fixedSize()
        .help(helpText(paired: paired, state: state))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lumière du pad")
    }

    private var noteText: String {
        let label = controller.positionLabel(for: position)
        guard label.contains(" · note "), let note = label.components(separatedBy: " · note ").last else { return "Note ?" }
        return "Note \(note)"
    }

    private func helpText(paired: Bool, state: LightState) -> String {
        var parts = [noteText]
        if let channel = controller.lightChannel(forColumn: position.column) { parts.append("canal LightKey \(channel)") }
        parts.append(paired ? "appairée" : "non appairée")
        switch state {
        case .on: parts.append("allumée dans LightKey")
        case .off: parts.append("éteinte dans LightKey")
        case .unknown: break
        }
        return parts.joined(separator: " · ")
    }
}

/// « Nouvel appui » d'un pad son et lumière : un seul menu pour le son (relancer ou arrêter) et pour la cue (n'allumer que si elle
/// est éteinte, ou basculer à chaque appui).
private struct MixedRetriggerMenu: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad
    let clip: AudioClip

    var body: some View {
        Menu {
            Picker(
                "Son",
                selection: Binding(get: { clip.retrigger }, set: { controller.setRetrigger(at: position, $0) })
            ) {
                Text("Son : relancer").tag(RetriggerBehavior.restart)
                Text("Son : arrêter").tag(RetriggerBehavior.stop)
            }
            .pickerStyle(.inline)
            Picker(
                "Lumière",
                selection: Binding(
                    get: { pad.lightRetrigger }, set: { controller.setLightRetrigger(at: position, to: $0) })
            ) {
                Text("Lumière : allumer seulement").tag(LightRetrigger.turnOnOnly)
                Text("Lumière : basculer à chaque appui").tag(LightRetrigger.toggle)
            }
            .pickerStyle(.inline)
        } label: {
            Text("Nouvel appui")
                .font(.system(size: 11))
                .foregroundStyle(Surface.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Si on rejoue ce pad : le son repart ou s'arrête ; la cue ne s'envoie que si LightKey la dit éteinte, ou à chaque appui")
        .accessibilityLabel("Nouvel appui")
    }
}

/// Type du pad (Son · Lumière · Les deux), dans une colonne **son et lumière** seulement ; une conversion qui retire quelque chose
/// demande confirmation (même feuille que pour une colonne).
private struct PadKindControl: View {
    @Environment(ShowController.self) private var controller
    @Environment(ConversionPrompter.self) private var prompter
    let position: GridPosition
    let pad: Pad

    var body: some View {
        if controller.currentGrid.columns[position.column].kind == .mixed, !controller.isLocked {
            Picker(
                "Type du pad",
                selection: Binding(
                    get: { pad.kind }, set: { prompter.requestPadKind(at: position, to: $0, controller: controller) })
            ) {
                Text("Son").tag(PadKind.audio)
                Text("Lumière").tag(PadKind.light)
                Text("Les deux").tag(PadKind.mixed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 170)
            .help("Type du pad : son seul, lumière seule, ou les deux à la fois")
            .accessibilityLabel("Type du pad")
        }
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

    private var isEditable: Bool { !controller.isLocked }

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
        .onChange(of: controller.isLocked) { editing = nil }
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
                .help(isEditable ? hint : "")
                .interactiveCursor(.horizontalText, enabled: isEditable)
                .onTapGesture(count: 2) { if isEditable { start(field) } }
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
        HStack(spacing: 10) {
            // Lecture, pause, stop et boucle forment un seul bloc.
            HStack(spacing: 4) {
                Button {
                    controller.playPad(at: position)
                } label: {
                    (isPlaying ? Icon.restart : Icon.playFill).view(size: 18)
                        .frame(width: 40, height: 40)
                        .background(pad.tint.vividColor, in: .circle)
                        .foregroundStyle(Surface.window)
                }
                .buttonStyle(.plain)
                .interactiveCursor(.link)
                .help(HelpText.play(isPlaying: isPlaying) + " (Retour)")
                .accessibilityLabel(isPlaying ? "Relancer" : "Lecture")

                groupButton(
                    .pauseFill, label: HelpText.pause(isPaused: isPaused), help: HelpText.pause(isPaused: isPaused) + " (Espace)",
                    active: isPaused, tint: pad.tint.vividColor
                ) {
                    controller.togglePause(at: position)
                }
                .disabled(event == nil)
                groupButton(.stopFill, label: "Stop", help: "Arrêter le son (fondu de 40 ms)", active: false, tint: Surface.textSecondary) {
                    controller.stop(at: position)
                }
                .disabled(event == nil)

                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 16).padding(.horizontal, 2)
                    .accessibilityHidden(true)

                groupButton(
                    .loop, label: "Boucle",
                    help: controller.isLocked ? HelpText.lockedReason : HelpText.loop(isOn: clip.loops),
                    active: clip.loops, tint: Surface.loopAccent
                ) {
                    controller.setLoops(at: position, !clip.loops)
                }
                .disabled(controller.isLocked)
                .accessibilityValue(clip.loops ? "activée" : "désactivée")
            }
            .padding(.horizontal, 4)
            .frame(height: 46)
            .background(Surface.well, in: .capsule)

            timeLabel(event)
        }
        .fixedSize()
    }

    private func groupButton(
        _ icon: Icon, label: String, help: String, active: Bool, tint: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            icon.view(size: icon == .loop ? 16 : 15)
                .frame(width: 36, height: 36)
                .background(active ? tint.opacity(0.22) : Color.clear, in: .circle)
                .foregroundStyle(active ? tint : Surface.textSecondary)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 18)
        .interactiveCursor(.link)
        .help(help)
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

// MARK: - Nouvel appui

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
            .help("Si on rejoue ce pad pendant qu'il sonne : le relancer depuis le début, ou l'arrêter")
        }
        .fixedSize()
    }
}

// MARK: - Couleur (popover) : un seul bouton, la pastille de la teinte en cours (sans son nom)

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
        .hoverHighlight(cornerRadius: 10)
        .interactiveCursor(.link)
        .help("Couleur du pad et intensité de la LED du contrôleur")
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
                        .interactiveCursor(.link)
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

private nonisolated struct Chevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// MARK: - Actions du pad

/// Couper, copier, coller, dupliquer, vider : un menu « trois petits points », avec les raccourcis affichés.
/// ⌫ (sans modifieur) reste géré par la grille : un raccourci sans modifieur volerait la touche Retour arrière
/// dans les champs de texte ; le menu propose donc ⌘⌫ pour « Vider ».
struct PadActionsMenu: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let hasPad: Bool

    var body: some View {
        Menu {
            PadEditActions(position: position, hasPad: hasPad)
        } label: {
            Icon.more.view(size: 18)
                .frame(width: 30, height: 30)
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Surface.textSecondary)
        .hoverHighlight(cornerRadius: 8)
        .help("Couper, copier, coller, dupliquer ou vider ce pad (\(controller.positionLabel(for: position)))")
        .accessibilityLabel("Actions du pad")
    }
}

/// Les cinq actions d'édition avec leurs raccourcis : menu « ⋯ » du panneau et menu contextuel des pads.
/// Elles agissent sur la sélection ; `position` devient la sélection au moment de l'action (clic droit sur un pad
/// qui n'était pas sélectionné).
struct PadEditActions: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let hasPad: Bool

    var body: some View {
        Button("Couper", icon: .cut) { act { controller.cutSelection() } }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(!hasPad)
        Button("Copier", icon: .copy) { act { controller.copySelection() } }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(!hasPad)
        Button("Coller", icon: .paste) { act { controller.pasteAtSelection() } }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(!controller.canPaste)
        Button("Dupliquer", icon: .duplicate) { act { controller.duplicateSelection() } }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!hasPad)
        Divider()
        Button("Vider", icon: .trash) { act { controller.clearSelection() } }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!hasPad)
    }

    private func act(_ action: () -> Void) {
        // Clic droit sur un pad déjà sélectionné : l'action vise toute la sélection ; sinon, ce pad seul.
        if !controller.selectedPositions.contains(position) { controller.selection = position }
        action()
    }
}

/// Barre du bas quand plusieurs pads sont sélectionnés (l'inspecteur ne règle qu'un pad à la fois).
struct MultiSelectionBar: View {
    @Environment(ShowController.self) private var controller

    var body: some View {
        let count = controller.selectedPadCount
        HStack(spacing: 12) {
            Icon.duplicate.view(size: 16).foregroundStyle(Surface.textSecondary)
            Text(count == 1 ? "1 pad sélectionné" : "\(count) pads sélectionnés")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Surface.textPrimary)
            Text("Glissez pour les déplacer, ⌥ pour les copier ; ⌘C / ⌘X / ⌘V, ⌘D et ⌫ agissent sur tout le groupe.")
                .font(.system(size: 11))
                .foregroundStyle(Surface.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Button("Désélectionner") { controller.selection = nil }
                .controlSize(.small)
            Menu {
                PadEditActions(position: controller.selection ?? GridPosition(column: 0, row: 0), hasPad: count > 0)
            } label: {
                Icon.more.view(size: 18).frame(width: 30, height: 30).contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(Surface.textSecondary)
            .accessibilityLabel("Actions sur la sélection")
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Surface.panel)
    }
}

/// Menu contextuel d'un pad de la grille : les principales actions du panneau du bas.
/// Verrouillé, seules les commandes de lecture restent (le reste serait refusé).
struct PadContextMenu: View {
    @Environment(ShowController.self) private var controller
    @Environment(ConversionPrompter.self) private var prompter
    let position: GridPosition

    var body: some View {
        let pad = controller.pad(at: position)
        let locked = controller.isLocked
        if let pad {
            if let clip = pad.audio {
                audioItems(pad: pad, clip: clip, locked: locked)
                if pad.light != nil {
                    Divider()
                    Button("Tester la cue", icon: .spotlight) { controller.testCue(at: position) }
                }
            } else {
                if !locked {
                    Button("Tester", icon: .spotlight) { controller.testCue(at: position) }
                    if controller.isPaired(at: position) {
                        Button("Retirer l'appairage") { controller.unpairCue(at: position) }
                    }
                    Divider()
                    colorMenu(pad: pad)
                }
            }
            if !locked {
                Divider()
                typeMenu(pad: pad)
                Divider()
                PadEditActions(position: position, hasPad: true)
            }
        } else if !locked {
            PadEditActions(position: position, hasPad: false)
        }
    }

    /// Type du pad : possible dans une colonne son et lumière ; ailleurs la colonne n'accepte qu'un type (grisé, avec la raison).
    @ViewBuilder
    private func typeMenu(pad: Pad) -> some View {
        let columnKind = controller.currentGrid.columns[position.column].kind
        if columnKind == .mixed {
            Menu("Type du pad") {
                ForEach([PadKind.audio, .light, .mixed], id: \.self) { kind in
                    let isCurrent = pad.kind == kind
                    let lossy = !isCurrent && !controller.conversionPlan(padAt: position, to: kind).isLossless
                    Button {
                        prompter.requestPadKind(at: position, to: kind, controller: controller)
                    } label: {
                        let name = kind == .audio ? "Son uniquement" : kind == .light ? "Lumière uniquement" : "Son et lumière"
                        Text((isCurrent ? "✓ " : "") + name + (lossy ? "…" : ""))
                    }
                    .disabled(isCurrent)
                }
            }
        } else {
            Button(columnKind == .audio ? "Type du pad — la colonne n'accepte que le son" : "Type du pad — la colonne n'accepte que la lumière") {}
                .disabled(true)
        }
    }

    @ViewBuilder
    private func audioItems(pad: Pad, clip: AudioClip, locked: Bool) -> some View {
        let state = controller.playback[pad.id]?.state
        let isPlaying: Bool = if case .playing = state { true } else { false }
        let isPaused = state?.isPausedState ?? false
        Button(isPlaying ? "Relancer" : "Lecture", icon: isPlaying ? .restart : .play) {
            controller.playPad(at: position)
        }
        Button(isPaused ? "Reprendre" : "Pause", icon: .pause) { controller.togglePause(at: position) }
            .disabled(state == nil)
        Button("Arrêter", icon: .stop) { controller.stop(at: position) }
            .disabled(state == nil)
        if !locked {
            Divider()
            Toggle(
                "Boucle",
                isOn: Binding(get: { clip.loops }, set: { controller.setLoops(at: position, $0) }))
            Picker(
                "Nouvel appui",
                selection: Binding(get: { clip.retrigger }, set: { controller.setRetrigger(at: position, $0) })
            ) {
                Text("Relancer").tag(RetriggerBehavior.restart)
                Text("Arrêter").tag(RetriggerBehavior.stop)
            }
            colorMenu(pad: pad)
        }
    }

    /// Les 16 teintes comme dans le popover du panneau (pastille : fond du pad + point vif), puis l'intensité de la LED.
    private func colorMenu(pad: Pad) -> some View {
        Menu("Couleur") {
            Picker(
                "Couleur",
                selection: Binding(get: { pad.tint }, set: { controller.updatePad(at: position, tint: $0) })
            ) {
                ForEach(Tint.allCases, id: \.self) { tint in
                    Label {
                        Text(tint.displayName)
                    } icon: {
                        Image(nsImage: TintSwatchImage.make(tint))
                    }
                    .tag(tint)
                }
            }
            .pickerStyle(.inline)
            Menu("Intensité de la LED") {
                Picker(
                    "Intensité de la LED",
                    selection: Binding(
                        get: { pad.ledIntensity }, set: { controller.updatePad(at: position, ledIntensity: $0) })
                ) {
                    ForEach(LEDIntensity.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.inline)
            }
        }
    }
}

/// Pastille d'une teinte en image (les menus n'affichent pas de vues SwiftUI) : coin arrondi à la couleur du fond
/// du pad, point à la couleur vive. Non « template » : la couleur est conservée.
private enum TintSwatchImage {
    @MainActor private static var cache: [Tint: NSImage] = [:]

    @MainActor static func make(_ tint: Tint) -> NSImage {
        if let cached = cache[tint] { return cached }
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            nsColor(tint.spec.surface).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4.5, yRadius: 4.5).fill()
            NSColor.white.withAlphaComponent(0.18).setStroke()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()
            nsColor(tint.spec.vivid).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 4.5, dy: 4.5)).fill()
            return true
        }
        image.isTemplate = false
        cache[tint] = image
        return image
    }

    private static func nsColor(_ rgb: RGB) -> NSColor {
        NSColor(
            srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
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
    /// Appelé à chaque position pendant le glisser : le son en cours de lecture suit tout de suite.
    let onLive: (Double) -> Void
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
                        .fill(Color(white: 0.82))
                        .frame(width: 26, height: handleHeight)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .offset(y: -CGFloat(position) * travel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let db = decibels(at: value.location.y, travel: travel)
                            draggedDB = db
                            onLive(db)
                        }
                        .onEnded { value in
                            draggedDB = nil
                            onCommit(decibels(at: value.location.y, travel: travel))
                        }
                )
                .onTapGesture(count: 2) { onCommit(0) }
                .interactiveCursor(draggedDB == nil ? .grabIdle : .grabActive)
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
        .help("Volume de ce pad, réglé en direct (indépendant du fader de colonne) — double-clic : 0 dB.")
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
        audio: AudioClip(fileName: "essai.wav", trimStart: 0.4, trimEnd: 5.2, fadeIn: 0.8, fadeOut: 1.4, loops: true))
    let controller = ShowController(show: Show(name: "Essai", grids: [grid]), audioDirectory: directory)
    controller.selection = position
    return InspectorView(position: position)
        .environment(controller)
        .environment(ConversionPrompter())
        .frame(width: 1100, height: Metrics.inspectorHeight)
        .preferredColorScheme(.dark)
}

#Preview("Inspecteur — pad son et lumière (largeur minimale, 1047)") {
    Fonts.register()
    var grid = PadGrid.empty(name: "Essai")
    grid.columns[1] = Column.empty(name: "Scènes", kind: .mixed)
    let position = GridPosition(column: 1, row: 2)
    grid[position] = Pad(
        title: "Orage lointain", subtitle: "Tonnerre + éclairs", tint: .azur,
        audio: AudioClip(fileName: "essai.wav", trimStart: 0.4, trimEnd: 5.2, fadeIn: 0.8, fadeOut: 1.4, loops: true),
        light: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0), isPaired: true))
    let controller = ShowController(show: Show(name: "Essai", grids: [grid]))
    controller.selection = position
    return InspectorView(position: position)
        .environment(controller)
        .environment(ConversionPrompter())
        .frame(width: 1047, height: Metrics.inspectorHeight)
        .preferredColorScheme(.dark)
}

#Preview("Inspecteur — pad lumière dans une colonne son et lumière") {
    Fonts.register()
    var grid = PadGrid.empty(name: "Essai")
    grid.columns[1] = Column.empty(name: "Scènes", kind: .mixed)
    let position = GridPosition(column: 1, row: 2)
    grid[position] = Pad(
        title: "Noir", subtitle: "Cue", tint: .graphite, light: .blank, awaitsSound: true)
    let controller = ShowController(show: Show(name: "Essai", grids: [grid]))
    controller.selection = position
    return InspectorView(position: position)
        .environment(controller)
        .environment(ConversionPrompter())
        .frame(width: 1047, height: Metrics.inspectorHeight)
        .preferredColorScheme(.dark)
}
