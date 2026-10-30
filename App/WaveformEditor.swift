import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Forme d'onde pleine largeur : zones élaguées assombries, poignées d'élagage déplaçables,
/// courbes de fondu en pointillés, tête de lecture blanche pendant la lecture.
/// Un glisser de poignée = une seule modification (⌘Z), enregistrée au relâchement.
struct WaveformEditor: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let clip: AudioClip
    let tint: Tint
    let event: PlaybackEvent?
    let waveform: Waveform?

    @State private var draggedStart: TimeInterval?
    @State private var draggedEnd: TimeInterval?

    private var duration: TimeInterval { max(waveform?.duration ?? 0, 0.001) }
    private var start: TimeInterval { draggedStart ?? clip.trimStart }
    private var end: TimeInterval { draggedEnd ?? clip.trimEnd ?? duration }

    var body: some View {
        VStack(spacing: 4) {
            ruler
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in drawWave(in: &context, size: size) }
                    trimmedShade(width: width)
                    fadeCurves(width: width, height: height)
                    handle(at: start, width: width, height: height, isStart: true)
                    handle(at: end, width: width, height: height, isStart: false)
                    playhead(width: width, height: height)
                }
                .coordinateSpace(.named("wave"))
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
                Text(AudioLibrary.formatDuration(duration * Double(step) / 4))
                    .font(Typography.mono)
                    .foregroundStyle(Surface.textTertiary)
                if step < 4 { Spacer(minLength: 0) }
            }
        }
        .accessibilityHidden(true)
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
            if let fadeIn = clip.fadeIn {
                path.move(to: CGPoint(x: x(start, width), y: height))
                path.addLine(to: CGPoint(x: x(min(start + fadeIn, end), width), y: 2))
            }
            if let fadeOut = clip.fadeOut {
                path.move(to: CGPoint(x: x(max(end - fadeOut, start), width), y: 2))
                path.addLine(to: CGPoint(x: x(end, width), y: height))
            }
        }
        .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        .allowsHitTesting(false)
    }

    private func handle(at time: TimeInterval, width: CGFloat, height: CGFloat, isStart: Bool) -> some View {
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
                        let t = Double(min(max(value.location.x, 0), width) / width) * duration
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

    @ViewBuilder
    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        if let event, event.state.isActive {
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
