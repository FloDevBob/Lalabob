import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Forme d'onde pleine hauteur : zones élaguées assombries, poignées d'élagage déplaçables,
/// tête de lecture blanche (un clic ou un glisser sur l'onde la déplace), et fondus réglés directement sous la courbe :
/// - une puce « Fondu » en bas à gauche (entrée) et en bas à droite (sortie) : un clic l'active ;
/// - une fois actif, une poignée au bout de la courbe pointillée en règle la durée, et une croix le retire.
/// Un glisser = une seule modification annulable (⌘Z), enregistrée au relâchement.
/// Verrouillé, seules les poignées d'élagage disparaissent : fondus et tête de lecture restent utilisables.
struct WaveformEditor: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let clip: AudioClip
    let tint: Tint
    let event: PlaybackEvent?
    let waveform: Waveform?

    @State private var draggedStart: TimeInterval?
    @State private var draggedEnd: TimeInterval?
    @State private var draggedFadeIn: TimeInterval?
    @State private var draggedFadeOut: TimeInterval?
    /// Position (secondes dans le fichier) pointée pendant un clic ou un glisser sur l'onde.
    @State private var scrubTime: TimeInterval?

    /// Durée proposée quand on active un fondu.
    private static let defaultFade: TimeInterval = 1
    private static let minimumFade: TimeInterval = 0.1

    private var duration: TimeInterval { max(waveform?.duration ?? 0, 0.001) }
    private var start: TimeInterval { draggedStart ?? clip.trimStart }
    private var end: TimeInterval { draggedEnd ?? clip.trimEnd ?? duration }
    private var fadeIn: TimeInterval? { draggedFadeIn ?? clip.fadeIn }
    private var fadeOut: TimeInterval? { draggedFadeOut ?? clip.fadeOut }

    var body: some View {
        VStack(spacing: 3) {
            ruler
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in drawWave(in: &context, size: size) }
                    trimmedShade(width: width)
                    fadeCurves(width: width, height: height)
                    // Verrouillé : l'élagage est figé (ses poignées disparaissent) ; les fondus restent réglables.
                    if !controller.isLocked {
                        trimHandle(at: start, width: width, height: height, isStart: true)
                        trimHandle(at: end, width: width, height: height, isStart: false)
                    }
                    fadeHandle(isIn: true, width: width, height: height)
                    fadeHandle(isIn: false, width: width, height: height)
                    playhead(width: width, height: height)
                    fadeChip(isIn: true, width: width, height: height)
                    fadeChip(isIn: false, width: width, height: height)
                }
                .coordinateSpace(.named("wave"))
                .contentShape(.rect)
                // Le fond de l'onde : clic ou glisser = déplacer la tête de lecture. Les poignées et les puces,
                // plus « proches », gardent la priorité sur ce geste.
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("wave"))
                        .onChanged { scrubTime = time(atX: $0.location.x, width: width) }
                        .onEnded { value in
                            let target = time(atX: value.location.x, width: width)
                            controller.seek(at: position, toFileTime: target, fileDuration: duration)
                            scrubTime = nil
                        }
                )
                .clipShape(.rect(cornerRadius: 10))
            }
            .background(Surface.well, in: .rect(cornerRadius: 10))
            .overlay {
                if waveform == nil {
                    Text("Forme d'onde indisponible").font(.system(size: 11.5)).foregroundStyle(Surface.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Forme d'onde, élagage de \(AudioLibrary.formatDuration(start)) à \(AudioLibrary.formatDuration(end))")
    }

    // MARK: - Dessin

    private func x(_ time: TimeInterval, _ width: CGFloat) -> CGFloat {
        CGFloat(min(max(time / duration, 0), 1)) * width
    }

    private func time(atX x: CGFloat, width: CGFloat) -> TimeInterval {
        Double(min(max(x, 0), width) / max(width, 1)) * duration
    }

    private func drawWave(in context: inout GraphicsContext, size: CGSize) {
        guard let peaks = waveform?.peaks, !peaks.isEmpty else { return }
        let barWidth = size.width / CGFloat(peaks.count)
        let middle = size.height / 2
        var path = Path()
        for (index, peak) in peaks.enumerated() {
            let half = max(CGFloat(min(peak, 1)) * (size.height / 2 - 4), 0.5)
            path.addRect(CGRect(x: CGFloat(index) * barWidth, y: middle - half, width: max(barWidth - 0.5, 0.5), height: half * 2))
        }
        context.fill(path, with: .color(tint.vividColor.opacity(0.85)))
    }

    private var ruler: some View {
        HStack {
            ForEach(0..<5, id: \.self) { step in
                Text(rulerLabel(duration * Double(step) / 4))
                    .font(Typography.mono)
                    .foregroundStyle(Surface.textTertiary)
                if step < 4 { Spacer(minLength: 0) }
            }
        }
        .font(.system(size: 9.5))
        .accessibilityHidden(true)
    }

    /// Sons courts : secondes avec décimale (« 1,5 s ») pour ne pas tronquer ; sons longs : « 1:02 ».
    private func rulerLabel(_ time: TimeInterval) -> String {
        duration < 20 ? AudioLibrary.formatFade(time) : AudioLibrary.formatDuration(time)
    }

    private func trimmedShade(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.black.opacity(0.55)).frame(width: x(start, width))
            Rectangle().fill(Color.black.opacity(0.55)).frame(width: max(width - x(end, width), 0))
                .offset(x: x(end, width))
        }
        .allowsHitTesting(false)
    }

    private func fadeCurves(width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            if let fadeIn {
                path.move(to: CGPoint(x: x(start, width), y: height))
                path.addLine(to: CGPoint(x: x(min(start + fadeIn, end), width), y: 4))
            }
            if let fadeOut {
                path.move(to: CGPoint(x: x(max(end - fadeOut, start), width), y: 4))
                path.addLine(to: CGPoint(x: x(end, width), y: height))
            }
        }
        .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        .allowsHitTesting(false)
    }

    // MARK: - Élagage

    private func trimHandle(at time: TimeInterval, width: CGFloat, height: CGFloat, isStart: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.white)
            .frame(width: 4, height: height)
            .overlay(alignment: isStart ? .topLeading : .topTrailing) {
                Capsule().fill(.white).frame(width: 12, height: 18)
            }
            .contentShape(.rect.inset(by: -8))
            .offset(x: x(time, width) - 2)
            .gesture(
                DragGesture(coordinateSpace: .named("wave"))
                    .onChanged { value in
                        let t = self.time(atX: value.location.x, width: width)
                        if isStart { draggedStart = t } else { draggedEnd = t }
                    }
                    .onEnded { _ in
                        controller.setTrim(at: position, start: start, end: end, fileDuration: duration)
                        draggedStart = nil
                        draggedEnd = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(isStart ? "Début de l'élagage" : "Fin de l'élagage")
            .accessibilityValue(AudioLibrary.formatDuration(time))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.1 : -0.1
                controller.setTrim(
                    at: position, start: isStart ? start + step : start, end: isStart ? end : end + step, fileDuration: duration)
            }
    }

    // MARK: - Fondus

    /// Durée maximale d'un fondu : ce qui reste de la partie jouée une fois l'autre fondu compté.
    private func fadeLimit(isIn: Bool) -> TimeInterval {
        max((end - start) - ((isIn ? fadeOut : fadeIn) ?? 0), Self.minimumFade)
    }

    private func setFade(isIn: Bool, to value: TimeInterval?) {
        let newIn = isIn ? (value ?? 0) : (clip.fadeIn ?? 0)
        let newOut = isIn ? (clip.fadeOut ?? 0) : (value ?? 0)
        controller.setFades(at: position, in: newIn, out: newOut)
    }

    /// Puce sous la courbe : « + Fondu » quand il n'y a pas de fondu, sinon la durée avec une croix pour le retirer.
    private func fadeChip(isIn: Bool, width: CGFloat, height: CGFloat) -> some View {
        let value = isIn ? fadeIn : fadeOut
        let name = isIn ? "Fondu d'entrée" : "Fondu de sortie"
        return HStack(spacing: 4) {
            if let value {
                Text(AudioLibrary.formatFade(value))
                    .font(.system(size: 10, design: .monospaced)).monospacedDigit()
                Button {
                    setFade(isIn: isIn, to: nil)
                } label: {
                    Icon.close.view(size: 9)
                }
                .buttonStyle(.plain)
                .help("Retirer le \(name.lowercased())")
                .accessibilityLabel("Retirer le \(name.lowercased())")
            } else {
                Button {
                    setFade(isIn: isIn, to: min(Self.defaultFade, fadeLimit(isIn: isIn)))
                } label: {
                    HStack(spacing: 3) {
                        Icon.plus.view(size: 9)
                        Text("Fondu").font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .help("Ajouter un \(name.lowercased())")
                .accessibilityLabel("Ajouter un \(name.lowercased())")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(.black.opacity(0.55), in: .capsule)
        .overlay(Capsule().stroke(.white.opacity(value == nil ? 0.12 : 0.35)))
        .foregroundStyle(value == nil ? Surface.textSecondary : .white)
        .fixedSize()
        .position(
            x: isIn ? x(start, width) + 14 + chipHalfWidth(isActive: value != nil) : x(end, width) - 14 - chipHalfWidth(isActive: value != nil),
            y: height - 14
        )
    }

    private func chipHalfWidth(isActive: Bool) -> CGFloat { isActive ? 30 : 28 }

    /// Poignée au bout de la courbe de fondu : glisser en change la durée.
    @ViewBuilder
    private func fadeHandle(isIn: Bool, width: CGFloat, height: CGFloat) -> some View {
        if let value = isIn ? fadeIn : fadeOut {
            let handleTime = isIn ? start + value : end - value
            Circle()
                .fill(.white)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 1))
                .contentShape(.circle.inset(by: -8))
                .position(x: x(min(max(handleTime, start), end), width), y: 4)
                .gesture(
                    DragGesture(coordinateSpace: .named("wave"))
                        .onChanged { drag in
                            let t = time(atX: drag.location.x, width: width)
                            let wanted = isIn ? t - start : end - t
                            let clamped = min(max(wanted, Self.minimumFade), fadeLimit(isIn: isIn))
                            if isIn { draggedFadeIn = clamped } else { draggedFadeOut = clamped }
                        }
                        .onEnded { _ in
                            setFade(isIn: isIn, to: isIn ? draggedFadeIn : draggedFadeOut)
                            draggedFadeIn = nil
                            draggedFadeOut = nil
                        }
                )
                .accessibilityElement()
                .accessibilityLabel(isIn ? "Durée du fondu d'entrée" : "Durée du fondu de sortie")
                .accessibilityValue(AudioLibrary.formatFade(value))
                .accessibilityAdjustableAction { direction in
                    let step = direction == .increment ? 0.1 : -0.1
                    setFade(isIn: isIn, to: min(max(value + step, Self.minimumFade), fadeLimit(isIn: isIn)))
                }
        }
    }

    /// Tête de lecture : suit le son ; pendant un clic ou un glisser, elle suit le pointeur (et le son ne bouge
    /// qu'au relâchement, pour ne pas hacher l'audio).
    @ViewBuilder
    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        if let scrubTime {
            Rectangle().fill(.white).frame(width: 2, height: height).offset(x: x(scrubTime, width) - 1)
                .allowsHitTesting(false)
        } else if let event, event.state.isActive {
            TimelineView(.animation(paused: event.state.isPausedState)) { _ in
                let elapsed = event.state.elapsedTime(now: ProcessInfo.processInfo.systemUptime)
                let span = max(end - start, 0.001)
                let time = start + (clip.loops ? elapsed.truncatingRemainder(dividingBy: span) : min(elapsed, span))
                Rectangle().fill(.white).frame(width: 2, height: height).offset(x: x(time, width) - 1)
            }
            .allowsHitTesting(false)
        }
    }
}

extension PlaybackState {
    var isPausedState: Bool {
        if case .paused = self { true } else { false }
    }

    /// Temps écoulé en secondes.
    func elapsedTime(now: TimeInterval) -> TimeInterval {
        switch self {
        case .idle: 0
        case .playing(let startedAt): now - startedAt
        case .paused(let elapsed): elapsed
        }
    }
}
