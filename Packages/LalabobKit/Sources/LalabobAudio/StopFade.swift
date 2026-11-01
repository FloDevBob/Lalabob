import Foundation

/// Fondu de sortie très bref appliqué à l'arrêt d'un son (bouton Stop, nouvel appui « Arrêter », « Tout arrêter »,
/// menu) : une coupure nette à un instant quelconque de l'onde fait un « clac » ; descendre à zéro en 40 ms l'évite
/// sans qu'on perçoive un retard. Pure, donc testable ; le moteur l'applique au volume du lecteur.
public enum StopFade {
    /// Durée du fondu (secondes). Assez court pour ne rien retarder à l'oreille, assez long pour supprimer le clic.
    public static let duration: TimeInterval = 0.04

    /// Gain (1 → 0) après `elapsed` secondes d'arrêt : quart de cosinus (puissance constante, sans cassure au départ).
    /// Un temps invalide ou négatif donne 1 (le son n'est pas touché).
    public static func gain(elapsed: TimeInterval) -> Float {
        guard elapsed.isFinite, elapsed > 0 else { return 1 }
        guard elapsed < duration else { return 0 }
        return Float(cos(elapsed / duration * .pi / 2))
    }
}
