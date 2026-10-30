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
        let text = abs(db).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR")))
        return (db < -0.05 ? "−" : "") + (db < -0.05 ? text : "0,0") + " dB"
    }
}
