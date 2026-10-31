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

    // MARK: - Sélection multiple : presse-papiers (⌘X, ⌘C, ⌘V, ⌘D, ⌫), déplacer, copier en bloc

    /// Positions sélectionnées qui contiennent un pad, colonne par colonne, de haut en bas.
    private var selectedFilledPositions: [GridPosition] {
        selectedPositions.filter { pad(at: $0) != nil }.sorted { ($0.column, $0.row) < ($1.column, $1.row) }
    }

    /// Nombre de pads (cases non vides) dans la sélection.
    public var selectedPadCount: Int { selectedFilledPositions.count }

    public func copySelection() {
        guard !refuseWhileLocked() else { return }
        let filled = selectedFilledPositions
        guard let left = filled.map(\.column).min(), let top = filled.map(\.row).min() else { return }
        clipboard = filled.compactMap { position in
            pad(at: position).map {
                ClipboardEntry(pad: $0, columnOffset: position.column - left, rowOffset: position.row - top)
            }
        }
    }

    public func cutSelection() {
        guard !refuseWhileLocked() else { return }
        copySelection()
        clearSelection()
    }

    /// Colle des copies des pads du presse-papiers à partir du coin haut-gauche de la sélection, en gardant leur
    /// disposition. Ce qui sort de la grille ou tombe dans une colonne d'un autre type (son / lumière) est ignoré,
    /// le reste est collé ; une seule annulation. `false` si rien n'a pu être collé.
    @discardableResult
    public func pasteAtSelection() -> Bool {
        guard !refuseWhileLocked(), let clipboard,
            let column = selectedPositions.map(\.column).min(), let row = selectedPositions.map(\.row).min()
        else { return false }
        return commit("Coller") { show, grid in
            var placedAny = false
            for entry in clipboard {
                let target = GridPosition(column: column + entry.columnOffset, row: row + entry.rowOffset)
                guard target.isValid, show.grids[grid].columns[target.column].kind == entry.pad.kind else { continue }
                show.grids[grid][target] = entry.pad.duplicated()
                placedAny = true
            }
            return placedAny
        }
    }

    /// Duplique chaque pad sélectionné dans la première case libre en dessous de lui, et sélectionne les copies.
    @discardableResult
    public func duplicateSelection() -> Bool {
        guard !refuseWhileLocked() else { return false }
        let sources = selectedFilledPositions
        guard !sources.isEmpty else { return false }
        var copies: [GridPosition] = []
        let done = commit("Dupliquer") { show, grid in
            for source in sources {
                guard let original = show.grids[grid][source] else { continue }
                let free = ((source.row + 1)..<PadGrid.size)
                    .map { GridPosition(column: source.column, row: $0) }
                    .first { show.grids[grid][$0] == nil }
                guard let free else { continue }
                show.grids[grid][free] = original.duplicated()
                copies.append(free)
            }
            return !copies.isEmpty
        }
        if done { selectPositions(copies) }
        return done
    }

    /// Vide toutes les cases sélectionnées (une seule annulation).
    @discardableResult
    public func clearSelection() -> Bool {
        let targets = selectedPositions
        guard !targets.isEmpty else { return false }
        return commit("Vider") { show, grid in
            var changed = false
            for position in targets where position.isValid && show.grids[grid][position] != nil {
                show.grids[grid][position] = nil
                changed = true
            }
            return changed
        }
    }

    /// Glisser un pad. Seul : déplace ou échange (voir `movePad`). S'il fait partie d'une sélection de plusieurs
    /// pads, tout le groupe suit du même décalage (une case sélectionnée ou libre en destination ; refusé si le
    /// groupe sortirait de la grille, changerait de type de colonne ou écraserait un pad hors sélection).
    /// La sélection suit les pads déplacés.
    @discardableResult
    public func moveSelection(from source: GridPosition, to target: GridPosition) -> Bool {
        guard selectedPositions.contains(source), selectedPositions.count > 1 else {
            let done = movePad(from: source, to: target)
            if done { selection = target }
            return done
        }
        let columnShift = target.column - source.column
        let rowShift = target.row - source.row
        guard columnShift != 0 || rowShift != 0 else { return false }
        let moving = selectedFilledPositions
        let done = commit("Déplacer les pads") { show, grid in
            let staying = Set(moving)
            var plan: [(from: GridPosition, to: GridPosition, pad: Pad)] = []
            for from in moving {
                let to = GridPosition(column: from.column + columnShift, row: from.row + rowShift)
                guard to.isValid, let pad = show.grids[grid][from],
                    show.grids[grid].columns[to.column].kind == pad.kind
                else { return false }
                if show.grids[grid][to] != nil, !staying.contains(to) { return false }
                plan.append((from, to, pad))
            }
            for step in plan { show.grids[grid][step.from] = nil }
            for step in plan { show.grids[grid][step.to] = step.pad }
            return true
        }
        if done { shiftSelection(columns: columnShift, rows: rowShift, anchor: source) }
        return done
    }

    /// ⌥-glisser : copie le groupe sélectionné du même décalage, dans des cases libres (refusé sinon).
    /// Un pad seul est copié comme avant (`duplicatePad`). La sélection passe sur les copies.
    @discardableResult
    public func duplicateSelection(from source: GridPosition, to target: GridPosition) -> Bool {
        guard selectedPositions.contains(source), selectedPositions.count > 1 else {
            let done = duplicatePad(from: source, to: target)
            if done { selection = target }
            return done
        }
        let columnShift = target.column - source.column
        let rowShift = target.row - source.row
        guard columnShift != 0 || rowShift != 0 else { return false }
        let moving = selectedFilledPositions
        let done = commit("Copier les pads") { show, grid in
            var plan: [(to: GridPosition, pad: Pad)] = []
            for from in moving {
                let to = GridPosition(column: from.column + columnShift, row: from.row + rowShift)
                guard to.isValid, let pad = show.grids[grid][from], show.grids[grid][to] == nil,
                    show.grids[grid].columns[to.column].kind == pad.kind
                else { return false }
                plan.append((to, pad.duplicated()))
            }
            for step in plan { show.grids[grid][step.to] = step.pad }
            return true
        }
        if done { shiftSelection(columns: columnShift, rows: rowShift, anchor: source) }
        return done
    }

    /// Décale toute la sélection (les cases qui sortiraient de la grille sont abandonnées) ; la case principale
    /// reste celle qui était sous le pointeur si elle est toujours dans la grille.
    private func shiftSelection(columns: Int, rows: Int, anchor: GridPosition) {
        func shifted(_ position: GridPosition) -> GridPosition {
            GridPosition(column: position.column + columns, row: position.row + rows)
        }
        let ordered = selectedPositions.sorted { ($0.column, $0.row) < ($1.column, $1.row) }.map(shifted).filter(\.isValid)
        let primary = shifted(anchor)
        selectPositions(ordered.contains(primary) ? [primary] + ordered.filter { $0 != primary } : ordered)
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

    /// Renomme une colonne de la grille affichée (nom vide refusé, 80 caractères au plus ; une seule annulation).
    public func renameColumn(at index: Int, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumTextLength))
        commit("Renommer la colonne") { show, grid in
            guard show.grids[grid].columns.indices.contains(index), !trimmed.isEmpty else { return false }
            show.grids[grid].columns[index].name = trimmed
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
