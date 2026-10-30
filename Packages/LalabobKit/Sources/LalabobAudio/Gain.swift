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
}
