import Foundation
import LalabobModel

/// Mode « Appairage lumière » : on rattache les cases lumière de Lalabob aux cues de LightKey.
///
/// Un aller-retour avec LightKey, d'où un mode et non une fenêtre : dans LightKey, « Add Trigger… » sur une cue ;
/// dans Lalabob, un appui sur le pad (contrôleur ou ampoule à l'écran) envoie la note. La case sélectionnée est la cible :
/// elle est appairée quand LightKey répond pour sa note (retour d'état), ou quand l'utilisateur le confirme (une cue éteinte
/// peut ne rien répondre). Puis on la nomme, et la case libre suivante est sélectionnée.
///
/// Tout passe par `ShowController` (⌘Z) ; refusé verrouillé, et verrouiller quitte le mode.
extension ShowController {
    /// Entre dans le mode d'appairage ou en sort. Refusé verrouillé.
    public func setPairingLights(_ active: Bool) {
        if active, refuseWhileLocked() { return }
        isPairingLights = active
        pairingNaming = nil
        if active, !(selection.map(isLightCell) ?? false) {
            selection = nextUnpairedLightPosition(after: nil)
        }
    }

    /// La case est dans une colonne lumière de la grille affichée.
    public func isLightCell(_ position: GridPosition) -> Bool {
        position.isValid && currentGrid.columns[position.column].kind == .light
    }

    /// La cue de la case est marquée appairée.
    public func isPaired(at position: GridPosition) -> Bool {
        guard let pad = pad(at: position), case .light(let cue) = pad.content else { return false }
        return cue.isPaired
    }

    /// Clic sur l'ampoule d'une case lumière : la case devient la cible et la note part vers LightKey.
    public func pairingSend(at position: GridPosition) {
        guard isPairingLights, !isLocked, isLightCell(position) else { return }
        selection = position
        lightPressHandler?(position)
    }

    /// Appui sur le contrôleur (la session l'a déjà relayé à LightKey) : la case devient la cible.
    func pairingPress(at position: GridPosition) {
        guard isPairingLights, !isLocked, isLightCell(position) else { return }
        selection = position
    }

    /// LightKey a répondu pour cette case : si c'est la cible, elle est appairée.
    func lightFeedbackArrived(at position: GridPosition) {
        guard isPairingLights, !isLocked, selection == position, !isPaired(at: position) else { return }
        pairCue(at: position)
    }

    /// Appairage confirmé à la main (« C'est appairé ») pour la case cible.
    @discardableResult
    public func confirmPairing() -> Bool {
        guard isPairingLights, let target = selection else { return false }
        return pairCue(at: target)
    }

    /// Marque la cue de la case comme appairée (la crée si la case est libre) : une seule annulation.
    @discardableResult
    func pairCue(at position: GridPosition) -> Bool {
        guard isPairingLights else { return false }
        let done = commit("Appairer la cue") { show, grid in
            guard position.isValid, show.grids[grid].columns[position.column].kind == .light else { return false }
            var pad = show.grids[grid][position] ?? Self.blankLightPad()
            guard case .light(var cue) = pad.content, !cue.isPaired else { return false }
            cue.isPaired = true
            pad.content = .light(cue: cue)
            show.grids[grid][position] = pad
            return true
        }
        if done { pairingNaming = position }
        return done
    }

    /// « Retirer l'appairage » : ne touche pas à LightKey.
    @discardableResult
    public func unpairCue(at position: GridPosition) -> Bool {
        commit("Retirer l'appairage") { show, grid in
            guard position.isValid, var pad = show.grids[grid][position], case .light(var cue) = pad.content, cue.isPaired else {
                return false
            }
            cue.isPaired = false
            pad.content = .light(cue: cue)
            show.grids[grid][position] = pad
            return true
        }
    }

    /// Le nom est saisi (ou abandonné) : la case libre suivante devient la cible.
    public func finishPairingNaming() {
        guard let named = pairingNaming else { return }
        pairingNaming = nil
        if let next = nextUnpairedLightPosition(after: named) { selection = next }
    }

    /// Première case lumière sans cue appairée après `position` (colonne par colonne, de haut en bas), ou la première de la grille.
    func nextUnpairedLightPosition(after position: GridPosition?) -> GridPosition? {
        let free = currentGrid.columns.indices
            .filter { currentGrid.columns[$0].kind == .light }
            .flatMap { column in (0..<PadGrid.size).map { GridPosition(column: column, row: $0) } }
            .filter { !isPaired(at: $0) }
        guard let position else { return free.first }
        return free.first { ($0.column, $0.row) > (position.column, position.row) }
    }
}
