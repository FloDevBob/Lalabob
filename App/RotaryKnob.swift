import LalabobDesign
import LalabobModel
import SwiftUI

/// Potard du filtre DJ d'une colonne son (`FilterCurve`), à côté du fader dans la carte de volume.
///
/// Repère au sommet = neutre ; l'arc, à la couleur de la colonne, part du sommet vers la gauche (passe-bas : il reste
/// les basses) ou vers la droite (passe-haut : il reste les aigus). Dessous, l'étiquette sur deux lignes : « Neutre »,
/// ou « Bas » / « Haut » et la coupure.
///
/// Glisser vers le haut ou la droite tourne vers le passe-haut, vers le bas ou la gauche vers le passe-bas ;
/// double-clic : retour au neutre. Flèches au clavier (navigation au clavier de macOS) et VoiceOver (réglable).
/// Reste utilisable verrouillé, comme le fader : on règle en jouant.
struct RotaryKnob: View {
    let name: String
    let accent: Color
    @Binding var value: Double
    let onReset: () -> Void

    @Environment(\.gridDensity) private var density
    @State private var dragStart: Double?

    /// Course de la souris (en points) pour aller du centre à une butée.
    private static let dragTravel: CGFloat = 100
    /// Pas des flèches du clavier et de VoiceOver.
    private static let step = 0.05
    /// Débattement de l'aiguille de part et d'autre du sommet.
    private static let sweep = 135.0

    /// Plus petit quand la piste des faders rétrécit (pads de hauteur minimale) : l'étiquette ne passe pas sous le
    /// bouton stop de la colonne.
    private var diameter: CGFloat { density.faderTrackHeight < 90 ? 28 : 36 }

    private var position: Double { FilterCurve.clamped(value) }
    private var mode: FilterCurve.Mode { FilterCurve.mode(for: position) }

    var body: some View {
        VStack(spacing: 3) {
            dial
                .frame(width: diameter, height: diameter)
                .contentShape(.circle)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let start = dragStart ?? position
                            if dragStart == nil { dragStart = start }
                            let delta = (drag.translation.width - drag.translation.height) / Self.dragTravel
                            value = FilterCurve.clamped(start + Double(delta))
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .onTapGesture(count: 2) { onReset() }
                .interactiveCursor(dragStart == nil ? .grabIdle : .grabActive)
                .help("Filtre de \(name) : glisser vers le haut (coupe les basses) ou vers le bas (coupe les aigus) · double-clic : neutre")
            caption
        }
        .frame(width: 42)
        .focusable()
        .onKeyPress(keys: [.leftArrow, .downArrow]) { _ in nudge(-Self.step) }
        .onKeyPress(keys: [.rightArrow, .upArrow]) { _ in nudge(Self.step) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Filtre de \(name)")
        .accessibilityValue(FilterCurve.label(for: position))
        .accessibilityHint("Vers la gauche : coupe les aigus. Vers la droite : coupe les basses.")
        .accessibilityAdjustableAction { direction in
            _ = nudge(direction == .increment ? Self.step : -Self.step)
        }
        .accessibilityAction(named: "Remettre au neutre") { onReset() }
    }

    @discardableResult
    private func nudge(_ amount: Double) -> KeyPress.Result {
        value = FilterCurve.clamped(position + amount)
        return .handled
    }

    private var dial: some View {
        // Le cercle de `trim` commence à 3 h et tourne dans le sens horaire ; tourné de 135°, il commence à 7 h 30 :
        // la piste fait 270° (0…0,75) et le sommet du potard est au milieu (0,375).
        let top = 0.375
        let reach = 0.375 * position
        let lineWidth: CGFloat = diameter < 32 ? 2.5 : 3
        let inset = lineWidth / 2
        return ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(inset)
            if position != 0 {
                Circle()
                    .trim(from: min(top, top + reach), to: max(top, top + reach))
                    .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(inset)
            }
            // Capuchon et aiguille.
            Circle()
                .fill(Color(white: 0.14))
                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                .padding(diameter * 0.2)
            Capsule()
                .fill(Color(white: 0.95))
                .frame(width: 2, height: diameter * 0.17)
                .offset(y: -diameter * 0.17)
                .rotationEffect(.degrees(Self.sweep * position))
        }
        .overlay(alignment: .top) {
            // Repère du neutre, au-dessus de la piste.
            Circle()
                .fill(Surface.textTertiary)
                .frame(width: 2.5, height: 2.5)
                .offset(y: -3.5)
        }
    }

    private var caption: some View {
        let (title, detail): (String, String?) =
            switch mode {
            case .neutral: ("Neutre", nil)
            case .lowPass(let cutoff): ("Bas", FilterCurve.formatFrequency(cutoff))
            case .highPass(let cutoff): ("Haut", FilterCurve.formatFrequency(cutoff))
            }
        return VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(detail == nil ? Surface.textTertiary : Surface.textPrimary)
            // Hauteur réservée même au neutre : l'étiquette ne fait pas sauter la carte.
            Text(detail ?? " ")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Surface.textSecondary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
