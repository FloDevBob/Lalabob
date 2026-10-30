import LalabobDesign
import LalabobEngine
import SwiftUI

/// Fader vertical d'une colonne son : rail, remplissage, poignée blanche arrondie, valeur en dB.
/// Reste utilisable verrouillé (le volume se règle en jouant). Double-clic : retour à 80 %.
struct VerticalFader: View {
    let name: String
    @Binding var level: Double
    static let defaultLevel = 0.8
    private let trackHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let height = geometry.size.height
                let travel = height - 20
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
