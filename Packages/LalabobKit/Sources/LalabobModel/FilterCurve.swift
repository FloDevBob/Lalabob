import Foundation

/// Filtre DJ à un seul potard, comme le bouton « Filter » de djay Pro : au centre le son est intact ; vers la gauche, un
/// passe-bas coupe les aigus (il reste les basses) ; vers la droite, un passe-haut coupe les basses (il reste les aigus).
///
/// La position va de −1 (tout à gauche) à +1 (tout à droite), 0 = neutre. La coupure suit une échelle logarithmique,
/// comme l'oreille : à gauche de 20 kHz à 200 Hz, à droite de 20 Hz à 5 kHz. Pure : utilisable par le moteur audio,
/// le contrôleur et l'interface, et testable hors ligne.
public enum FilterCurve {
    /// Coupure du passe-bas tout près du centre (le son est encore pratiquement intact).
    public static let lowPassMaximum: Double = 20_000
    /// Coupure du passe-bas tout à gauche : il ne reste que les basses.
    public static let lowPassMinimum: Double = 200
    /// Coupure du passe-haut tout près du centre.
    public static let highPassMinimum: Double = 20
    /// Coupure du passe-haut tout à droite : il ne reste que les aigus.
    public static let highPassMaximum: Double = 5_000
    /// Autour du centre, une position est ramenée au neutre (on retombe facilement sur « Neutre » à la souris).
    public static let neutralZone: Double = 0.04

    /// Ce que fait le filtre à une position donnée.
    public enum Mode: Equatable, Sendable {
        case neutral
        case lowPass(cutoff: Double)
        case highPass(cutoff: Double)
    }

    /// Position bornée à −1…+1 ; une valeur non numérique donne le neutre.
    public static func clamped(_ position: Double) -> Double {
        guard !position.isNaN else { return 0 }
        return min(max(position, -1), 1)
    }

    /// Position bornée et aimantée au centre (`neutralZone`) : c'est la valeur que retient le spectacle.
    public static func snapped(_ position: Double) -> Double {
        let value = clamped(position)
        return abs(value) < neutralZone ? 0 : value
    }

    public static func mode(for position: Double) -> Mode {
        let value = clamped(position)
        if value < 0 { return .lowPass(cutoff: cutoff(for: value)) }
        if value > 0 { return .highPass(cutoff: cutoff(for: value)) }
        return .neutral
    }

    /// Fréquence de coupure (Hz) à une position. Au neutre exact : `lowPassMaximum` (rien n'est coupé).
    public static func cutoff(for position: Double) -> Double {
        let value = clamped(position)
        if value < 0 { return logScale(from: lowPassMaximum, to: lowPassMinimum, amount: -value) }
        if value > 0 { return logScale(from: highPassMinimum, to: highPassMaximum, amount: value) }
        return lowPassMaximum
    }

    /// Étiquette de l'interface : « Neutre », « Bas 800 Hz », « Haut 2,1 kHz ».
    public static func label(for position: Double) -> String {
        switch mode(for: position) {
        case .neutral: "Neutre"
        case .lowPass(let cutoff): "Bas " + formatFrequency(cutoff)
        case .highPass(let cutoff): "Haut " + formatFrequency(cutoff)
        }
    }

    /// « 84 Hz », « 800 Hz » (dizaine près au-delà de 100 Hz), « 2,1 kHz », « 17 kHz » (virgule française).
    public static func formatFrequency(_ hertz: Double) -> String {
        guard hertz.isFinite, hertz > 0 else { return "0 Hz" }
        let rounded = hertz >= 100 ? (hertz / 10).rounded() * 10 : hertz.rounded()
        if rounded < 1000 { return "\(Int(rounded)) Hz" }
        if hertz >= 9_950 { return "\(Int((hertz / 1000).rounded())) kHz" }
        let tenths = Int((hertz / 100).rounded())
        let whole = tenths / 10, fraction = tenths % 10
        return fraction == 0 ? "\(whole) kHz" : "\(whole),\(fraction) kHz"
    }

    /// Interpolation logarithmique de `start` (amount 0) à `end` (amount 1), bornes exactes aux extrémités.
    private static func logScale(from start: Double, to end: Double, amount: Double) -> Double {
        if amount <= 0 { return start }
        if amount >= 1 { return end }
        return start * pow(end / start, amount)
    }
}
