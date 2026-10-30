import Foundation
import LalabobModel

/// Édition du spectacle. Chaque opération passe par `commit`, qui enregistre l'annulation (⌘Z),
/// garde l'onglet affiché valide et renvoie le spectacle au moteur audio (donc aux LED).
///
/// Les opérations renvoient `false` quand elles ne font rien (case invalide, mauvais type de colonne…).
extension ShowController {
    // MARK: - Pads

    /// Place un pad (glisser depuis la bibliothèque, coller). Remplace le pad déjà présent.
    /// Refusé si le type du pad ne correspond pas à la colonne (les sons ne vont pas dans les colonnes lumière).
    @discardableResult
    public func place(_ pad: Pad, at position: GridPosition) -> Bool {
        commit("Placer un pad") { show, grid in
            guard position.isValid, show.grids[grid].columns[position.column].kind == pad.kind else { return false }
            show.grids[grid][position] = pad
            return true
        }
    }

    /// Crée une cue lumière vide dans une case libre d'une colonne lumière.
    @discardableResult
    public func newLightCue(at position: GridPosition) -> Bool {
        guard pad(at: position) == nil else { return false }
        // La note envoyée à LightKey est celle du contrôleur (ADR 0004) : le message stocké ne sert pas.
        let cue = LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0))
        return place(Pad(title: "Nouvelle cue", tint: .ambre, content: .light(cue: cue)), at: position)
    }

    @discardableResult
    public func clearPad(at position: GridPosition) -> Bool {
        commit("Vider le pad") { show, grid in
            guard position.isValid, show.grids[grid][position] != nil else { return false }
            show.grids[grid][position] = nil
            return true
        }
    }

    /// Glisser un pad : déplace vers une case vide, échange avec un pad déjà présent.
    @discardableResult
    public func movePad(from source: GridPosition, to target: GridPosition) -> Bool {
        commit("Déplacer le pad") { show, grid in
            guard source != target, source.isValid, target.isValid, let moving = show.grids[grid][source] else {
                return false
            }
            let columns = show.grids[grid].columns
            guard columns[target.column].kind == moving.kind else { return false }
            let displaced = show.grids[grid][target]
            if let displaced, displaced.kind != columns[source.column].kind { return false }
            show.grids[grid][target] = moving
            show.grids[grid][source] = displaced
            return true
        }
    }

    /// ⌥-glisser : copie le pad (nouvel identifiant) dans une case vide.
    @discardableResult
    public func duplicatePad(from source: GridPosition, to target: GridPosition) -> Bool {
        guard let original = pad(at: source), pad(at: target) == nil else { return false }
        return place(original.duplicated(), at: target)
    }

    /// Inspecteur : titre, sous-titre, couleur, intensité LED. Les paramètres absents ne changent pas.
    @discardableResult
    public func updatePad(
        at position: GridPosition,
        title: String? = nil,
        subtitle: String? = nil,
        tint: Tint? = nil,
        ledIntensity: LEDIntensity? = nil
    ) -> Bool {
        commit("Modifier le pad") { show, grid in
            guard position.isValid, var pad = show.grids[grid][position] else { return false }
            if let title { pad.title = String(title.prefix(Self.maximumTextLength)) }
            if let subtitle { pad.subtitle = String(subtitle.prefix(Self.maximumTextLength)) }
            if let tint { pad.tint = tint }
            if let ledIntensity { pad.ledIntensity = ledIntensity }
            show.grids[grid][position] = pad
            return true
        }
    }

    nonisolated static let maximumTextLength = 80

    // MARK: - Presse-papiers (⌘X, ⌘C, ⌘V, ⌘D, ⌫)

    public func copySelection() {
        guard !refuseWhileLocked(), let selection, let pad = pad(at: selection) else { return }
        clipboard = pad
    }

    public func cutSelection() {
        guard !refuseWhileLocked(), let selection else { return }
        copySelection()
        clearPad(at: selection)
    }

    /// Colle une copie du pad du presse-papiers dans la case sélectionnée (remplace son contenu).
    @discardableResult
    public func pasteAtSelection() -> Bool {
        guard !refuseWhileLocked(), let selection, let clipboard else { return false }
        return place(clipboard.duplicated(), at: selection)
    }

    /// Duplique le pad sélectionné dans la première case libre en dessous, et sélectionne la copie.
    @discardableResult
    public func duplicateSelection() -> Bool {
        guard !refuseWhileLocked(), let selection, pad(at: selection) != nil else { return false }
        let below = ((selection.row + 1)..<PadGrid.size).map { GridPosition(column: selection.column, row: $0) }
        guard let free = below.first(where: { pad(at: $0) == nil }), duplicatePad(from: selection, to: free) else {
            return false
        }
        self.selection = free
        return true
    }

    @discardableResult
    public func clearSelection() -> Bool {
        guard let selection else { return false }
        return clearPad(at: selection)
    }

    public var canPaste: Bool { clipboard != nil && !isLocked }

    // MARK: - Onglets de grilles

    public func addGrid() {
        let name = "Grille \(show.grids.count + 1)"
        let added = commit("Ajouter une grille") { show, _ in
            guard show.grids.count < Show.maximumGridCount else { return false }
            show.grids.append(.empty(name: name))
            return true
        }
        if added { selectGrid(at: show.grids.count - 1) }
    }

    public func renameGrid(at index: Int, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumTextLength))
        commit("Renommer la grille") { show, _ in
            guard show.grids.indices.contains(index), !trimmed.isEmpty else { return false }
            show.grids[index].name = trimmed
            return true
        }
    }

    /// Réordonne les onglets ; l'onglet affiché reste le même.
    public func moveGrid(from source: Int, to destination: Int) {
        let displayed = currentGrid.id
        commit("Déplacer la grille") { show, _ in
            guard source != destination, show.grids.indices.contains(source), show.grids.indices.contains(destination)
            else { return false }
            let grid = show.grids.remove(at: source)
            show.grids.insert(grid, at: destination)
            return true
        }
        if let index = show.grids.firstIndex(where: { $0.id == displayed }) { selectGrid(at: index) }
    }

    /// Supprime un onglet (jamais le dernier).
    public func removeGrid(at index: Int) {
        commit("Supprimer la grille") { show, _ in
            guard show.grids.count > 1, show.grids.indices.contains(index) else { return false }
            show.grids.remove(at: index)
            return true
        }
    }
}

// MARK: - Libellés pour l'interface

extension ShowController {
    /// Nombre de pads d'un onglet (affiché sur l'onglet).
    public func padCount(inGrid index: Int) -> Int {
        guard show.grids.indices.contains(index) else { return 0 }
        return show.grids[index].columns.flatMap(\.slots).compactMap { $0 }.count
    }

    /// « Bruitages · ligne 6 · note 61 » : nom de la colonne, ligne, et note du contrôleur s'il est connu.
    public func positionLabel(for position: GridPosition) -> String {
        guard position.isValid else { return "" }
        var label = "\(currentGrid.columns[position.column].name) · ligne \(position.row + 1)"
        if let model = connectedController ?? lastControllerModel {
            label += " · note \(model.driver.note(for: position))"
        }
        return label
    }

    /// Ce son est-il déjà sur une grille du spectacle ? (point turquoise dans la bibliothèque)
    public func usesAudioFile(named fileName: String) -> Bool {
        let wanted = AudioClip.safeFileName(from: fileName)
        return show.grids.contains { grid in
            grid.columns.contains { column in
                column.slots.contains { pad in
                    if case .audio(let clip) = pad?.content { clip.fileName == wanted } else { false }
                }
            }
        }
    }
}
