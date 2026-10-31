import LalabobDesign
import LalabobEngine
import SwiftUI

/// Fader vertical d'une colonne son : rail, remplissage, poignée blanche arrondie, valeur en dB.
/// Avec `meterColumn`, le vumètre de la colonne (signal réel mesuré dans le moteur) est à droite du rail.
/// Reste utilisable verrouillé (le volume se règle en jouant). Double-clic : retour à 80 %.
struct VerticalFader: View {
    let name: String
    @Binding var level: Double
    var meterColumn: Int?
    static let defaultLevel = 0.8
    private let trackHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                track
                    .frame(width: 34)
                if let meterColumn {
                    LevelMeter(column: meterColumn)
                        .frame(width: 14)
                }
            }
            .frame(height: trackHeight)
            Text(Gain.formatDecibels(level: level))
                .font(Typography.mono)
                .foregroundStyle(Surface.textSecondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume de \(name)")
        .accessibilityValue(Gain.formatDecibels(level: level))
        .accessibilityAdjustableAction { direction in
            let step = 0.05
            level = min(max(level + (direction == .increment ? step : -step), 0), 1)
        }
    }

    private var track: some View {
        GeometryReader { geometry in
            let travel = geometry.size.height - 20
            ZStack(alignment: .bottom) {
                Capsule().fill(Surface.well).frame(width: 6)
                Capsule().fill(Surface.textSecondary.opacity(0.5))
                    .frame(width: 6, height: max(CGFloat(level) * travel + 10, 0))
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white)
                    .frame(width: 30, height: 20)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(y: -CGFloat(level) * travel)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    level = min(max(1 - Double((value.location.y - 10) / travel), 0), 1)
                }
            )
            .onTapGesture(count: 2) { level = Self.defaultLevel }
        }
    }
}

/// Vumètre stéréo d'une colonne (deux barres fines) : le signal réel après le fader, vert, ambre au-delà de 82 %,
/// rouge tout en haut (0 dB). Montée immédiate, descente progressive (`MeterBallistics`).
struct LevelMeter: View {
    @Environment(ShowController.self) private var controller
    let column: Int
    @State private var smoothing = MeterSmoothing()

    private static let gradient = Gradient(stops: [
        .init(color: Color(red: 0.24, green: 0.86, blue: 0.43), location: 0),
        .init(color: Color(red: 0.24, green: 0.86, blue: 0.43), location: 0.78),
        .init(color: Surface.lightAccent, location: 0.84),
        .init(color: Surface.lightAccent, location: 0.95),
        .init(color: Color(red: 1, green: 0.36, blue: 0.4), location: 1),
    ])

    var body: some View {
        let meters = controller.meters
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let levels = smoothing.update(
                at: timeline.date.timeIntervalSinceReferenceDate,
                left: Gain.meterFraction(forPeak: meters.peak(column: column, channel: 0)),
                right: Gain.meterFraction(forPeak: meters.peak(column: column, channel: 1)))
            HStack(spacing: 2) {
                bar(levels.left)
                bar(levels.right)
            }
        }
        .accessibilityHidden(true)
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Capsule().fill(Surface.well)
                Rectangle()
                    .fill(LinearGradient(gradient: Self.gradient, startPoint: .bottom, endPoint: .top))
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: geometry.size.height * fraction)
                    }
                    .clipShape(.capsule)
            }
        }
    }
}

/// Position affichée des deux barres. Classe simple, non observée : la vue se redessine par `TimelineView`, pas par
/// elle ; elle ne fait que se souvenir de l'image précédente pour la descente progressive.
@MainActor
final class MeterSmoothing {
    private var lastTime: Double?
    private var left = 0.0
    private var right = 0.0

    func update(at time: Double, left targetLeft: Double, right targetRight: Double) -> (left: Double, right: Double) {
        let elapsed = lastTime.map { time - $0 } ?? 0
        lastTime = time
        left = MeterBallistics.next(displayed: left, target: targetLeft, elapsed: elapsed)
        right = MeterBallistics.next(displayed: right, target: targetRight, elapsed: elapsed)
        return (left, right)
    }
}

/// Mini-égaliseur animé d'un pad en lecture (trois barres) ; figé si la lecture est en pause.
struct MiniEqualizer: View {
    let color: Color
    let isAnimating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !isAnimating)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = isAnimating ? (sin(t * (5 + Double(index) * 1.7) + Double(index) * 2) + 1) / 2 : 0.5
                    Capsule().fill(color).frame(width: 2.5, height: 4 + CGFloat(phase) * 8)
                }
            }
            .frame(height: 12, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}
