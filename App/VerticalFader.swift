import LalabobDesign
import LalabobEngine
import SwiftUI

/// Fader vertical d'une colonne : rail, remplissage, poignée blanche arrondie, valeur en dB (ou `valueText`).
/// `accessory` se place à droite du rail : le vumètre d'une colonne son (signal réel mesuré dans le moteur), le soleil
/// d'une colonne lumière. Reste utilisable verrouillé (on règle en jouant). Double-clic : retour à `defaultLevel`.
/// `hardwareMarker` : position réelle du fader physique tant qu'il n'a pas rejoint la valeur affichée (prise en main
/// progressive) ; un repère ambré sur le rail dit « amenez le fader jusqu'ici ».
struct VerticalFader<Accessory: View>: View {
    let name: String
    @Binding var level: Double
    var valueText: String?
    var defaultLevel = 0.8
    var hardwareMarker: Double?
    @ViewBuilder var accessory: () -> Accessory
    @Environment(\.gridDensity) private var density
    private var trackHeight: CGFloat { density.faderTrackHeight }

    private var shownValue: String { valueText ?? Gain.formatDecibels(level: level) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                track
                    .frame(width: 34)
                accessory()
            }
            .frame(height: trackHeight)
            Text(shownValue)
                .font(Typography.mono)
                .foregroundStyle(Surface.textSecondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume de \(name)")
        .accessibilityValue(shownValue)
        .accessibilityHint(hardwareMarker == nil ? "" : "Le fader physique n'a pas encore rejoint cette valeur : il est ignoré jusque-là.")
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
                if let hardwareMarker {
                    // Même repère que le centre de la poignée : le fader physique y est à la même hauteur.
                    Capsule().fill(Surface.lightAccent)
                        .frame(width: 34, height: 3)
                        .offset(y: -(CGFloat(hardwareMarker) * travel + 8.5))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    level = min(max(1 - Double((value.location.y - 10) / travel), 0), 1)
                }
            )
            .onTapGesture(count: 2) { level = defaultLevel }
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
