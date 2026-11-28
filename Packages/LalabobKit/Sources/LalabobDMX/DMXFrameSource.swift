import Foundation

/// Ce qui calcule la trame à un instant donné (la console lumière, J14 étape 3).
///
/// La sortie l'appelle à **chaque rafraîchissement**, sur son propre fil : un fondu avance même si l'interface rame.
/// Doit être rapide, sans verrou ni E/S. Une valeur (struct) est conseillée : la sortie en garde une copie.
public protocol DMXFrameSource: Sendable {
    /// `time` : secondes de `DMXClock`.
    func frame(at time: Double) -> DMXFrame
}

/// Horloge des fondus DMX : secondes écoulées depuis un instant fixe du processus, monotone (jamais remise à l'heure).
/// Le moteur s'en sert pour dater un appui, la sortie pour calculer la trame : les deux parlent du même temps.
public enum DMXClock {
    private static let origin = ContinuousClock.now

    public static func now() -> Double {
        seconds(ContinuousClock.now - origin)
    }

    static func seconds(_ duration: Duration) -> Double {
        let (s, atto) = duration.components
        return Double(s) + Double(atto) / 1e18
    }
}
