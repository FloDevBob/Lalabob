import Foundation

/// Prise en main progressive (« soft takeover ») des faders physiques.
///
/// Chaque grille a ses propres niveaux de colonne : après un changement d'onglet, un fader physique n'est plus
/// à la valeur affichée. Sans précaution, son premier mouvement ferait sauter le volume. Un fader « décroché »
/// est donc ignoré jusqu'à ce qu'il rejoigne la valeur de l'écran (à `threshold` près, ou en la traversant) ;
/// ensuite il suit normalement. Valeur pure : aucune E/S, testable sans matériel.
struct FaderPickup: Equatable, Sendable {
    /// Écart toléré entre le fader et l'écran pour s'accrocher (3 % de la course).
    static let threshold = 0.03

    /// Proche de l'écran, à une marge d'arrondi flottant près (0,80 − 0,77 vaut un peu plus que 0,03).
    private static func isClose(_ physical: Double, to screen: Double) -> Bool {
        abs(physical - screen) <= threshold + 1e-9
    }

    /// Dernière position connue de chaque fader physique (0…1), par colonne.
    private(set) var positions: [Int: Double] = [:]
    private var hooked: Set<Int> = []

    /// Les faders connus qui ne commandent pas encore leur colonne, avec leur position réelle (pour le repère à l'écran).
    var waiting: [Int: Double] { positions.filter { !hooked.contains($0.key) } }

    /// Mouvement d'un fader physique. Renvoie `true` si la valeur doit être appliquée à la colonne,
    /// `false` si le fader n'a pas encore rejoint la valeur de l'écran.
    mutating func move(column: Int, to physical: Double, screen: Double) -> Bool {
        let previous = positions[column]
        positions[column] = physical
        if hooked.contains(column) { return true }
        let close = Self.isClose(physical, to: screen)
        // Un mouvement rapide peut enjamber la valeur de l'écran entre deux messages.
        let crossed = previous.map { ($0 - screen) * (physical - screen) <= 0 } ?? false
        guard close || crossed else { return false }
        hooked.insert(column)
        return true
    }

    /// À rappeler dès que les niveaux affichés ont pu changer (autre onglet, souris, annulation, autre spectacle) :
    /// un fader n'est accroché que s'il est encore à la valeur de l'écran. `screenLevels[colonne]`.
    mutating func sync(screenLevels: [Double]) {
        for (column, physical) in positions where screenLevels.indices.contains(column) {
            if Self.isClose(physical, to: screenLevels[column]) {
                hooked.insert(column)
            } else {
                hooked.remove(column)
            }
        }
    }

    /// Positions déjà connues d'un autre spectacle (la session les garde d'une fenêtre à l'autre) ; rien n'est accroché
    /// d'office : `sync` décide.
    mutating func seed(_ known: [Int: Double]) {
        positions = known
        hooked = []
    }
}
