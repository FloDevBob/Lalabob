import Foundation

/// Conversions de niveaux. Pures, utilisables hors du thread audio.
public enum Gain {
    /// En dessous de ce seuil (dB), le son est considéré comme coupé.
    public static let silenceFloorDB: Double = -60

    /// Gain linéaire (amplitude) correspondant à des décibels. 0 dB → 1.
    public static func linear(fromDB db: Double) -> Float {
        guard db.isFinite, db > silenceFloorDB else { return 0 }
        return Float(pow(10, db / 20))
    }

    /// Niveau de fader borné à 0…1 (une valeur invalide donne le silence).
    public static func faderLevel(_ level: Double) -> Double {
        guard level.isFinite else { return 0 }
        return min(max(level, 0), 1)
    }

    /// Valeur d'un fader en décibels (le niveau est une amplitude linéaire), `nil` sous le seuil de silence.
    public static func decibels(forLevel level: Double) -> Double? {
        let level = faderLevel(level)
        guard level > 0 else { return nil }
        let db = 20 * log10(level)
        return db > silenceFloorDB ? db : nil
    }

    /// « −6,0 dB », « 0,0 dB », « −∞ dB » (virgule et vrai signe moins, comme dans l'interface).
    public static func formatDecibels(level: Double) -> String {
        guard let db = decibels(forLevel: level) else { return "−∞ dB" }
        return formatDecibels(db: db)
    }

    /// Même présentation pour un gain en dB (« +3,5 dB » au-dessus de zéro ; « −∞ dB » au plancher de silence).
    public static func formatDecibels(db: Double) -> String {
        let db = db.isNaN ? 0 : db
        guard db > silenceFloorDB else { return "−∞ dB" }
        let text = abs(db).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR")))
        if db < -0.05 { return "−" + text + " dB" }
        if db > 0.05 { return "+" + text + " dB" }
        return "0,0 dB"
    }

    // MARK: Jauge de volume d'un pad

    /// Plage de la jauge de volume d'un pad (−60 dB en bas, +12 dB en haut : 0 dB aux 5/6 de la course).
    public static let gaugeRangeDB: ClosedRange<Double> = -60...12

    /// Position 0…1 (de bas en haut) d'un gain en dB sur la jauge. Valeur non numérique : position de 0 dB.
    public static func gaugePosition(forDB db: Double) -> Double {
        let range = gaugeRangeDB
        let value = db.isNaN ? 0 : min(max(db, range.lowerBound), range.upperBound)
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    /// Gain en dB d'une position 0…1 de la jauge (bornée). Valeur non numérique : 0 dB.
    public static func decibels(forGaugePosition position: Double) -> Double {
        guard !position.isNaN else { return 0 }
        let range = gaugeRangeDB
        return range.lowerBound + min(max(position, 0), 1) * (range.upperBound - range.lowerBound)
    }
}
