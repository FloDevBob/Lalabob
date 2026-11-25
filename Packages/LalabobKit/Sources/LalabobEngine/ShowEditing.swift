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
            guard position.isValid, show.grids[grid].columns[position.column].kind.accepts(pad.kind) else { return false }
            show.grids[grid][position] = pad
            return true
        }
    }

    /// Crée une cue lumière vide dans une case libre d'une colonne lumière.
    @discardableResult
    public func newLightCue(at position: GridPosition) -> Bool {
        guard pad(at: position) == nil else { return false }
        return place(Self.blankLightPad(), at: position)
    }

    /// Une cue lumière vierge. La note envoyée à LightKey est celle du contrôleur (ADR 0006) : le message stocké ne sert pas.
    static func blankLightPad() -> Pad {
        Pad.cue(title: "Nouvelle cue", tint: .ambre, cue: .blank)
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
            guard columns[target.column].kind.accepts(moving.kind) else { return false }
            let displaced = show.grids[grid][target]
            if let displaced, !columns[source.column].kind.accepts(displaced.kind) { return false }
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
                guard target.isValid, show.grids[grid].columns[target.column].kind.accepts(entry.pad.kind) else { continue }
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

    /// Plan d'un glissé de groupe : pour chaque pad sélectionné, sa case d'arrivée (décalage identique). `nil` si le
    /// glissé serait refusé : case hors grille, colonne d'un autre type, pad hors groupe écrasé (déplacer) ou case
    /// occupée (copier : les cases libres sont exigées, même celles du groupe).
    private static func blockPlan(
        in grid: PadGrid, moving: [GridPosition], columnShift: Int, rowShift: Int, copying: Bool
    ) -> [(from: GridPosition, to: GridPosition, pad: Pad)]? {
        let leaving = Set(moving)
        var plan: [(from: GridPosition, to: GridPosition, pad: Pad)] = []
        for from in moving {
            let to = GridPosition(column: from.column + columnShift, row: from.row + rowShift)
            guard to.isValid, let pad = grid[from], grid.columns[to.column].kind.accepts(pad.kind) else { return nil }
            if grid[to] != nil, copying || !leaving.contains(to) { return nil }
            plan.append((from, to, pad))
        }
        return plan
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
            guard
                let plan = Self.blockPlan(
                    in: show.grids[grid], moving: moving, columnShift: columnShift, rowShift: rowShift, copying: false)
            else { return false }
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
            guard
                let plan = Self.blockPlan(
                    in: show.grids[grid], moving: moving, columnShift: columnShift, rowShift: rowShift, copying: true)
            else { return false }
            for step in plan { show.grids[grid][step.to] = step.pad.duplicated() }
            return true
        }
        if done { shiftSelection(columns: columnShift, rows: rowShift, anchor: source) }
        return done
    }

    // MARK: - Aperçu des cases cibles pendant un glisser de groupe

    /// Un glisser vient de commencer sur ce pad (mémorisé pour montrer, pendant le survol, où tomberait le groupe).
    public func beginDrag(from position: GridPosition) {
        draggedPosition = position
        dragPreview = nil
    }

    /// Met à jour l'aperçu quand le pointeur survole `target` : toutes les cases d'arrivée du groupe, et si le dépôt
    /// serait accepté. Pas d'aperçu pour un pad seul, un pad hors sélection ou un spectacle verrouillé.
    public func updateDragPreview(source: GridPosition, target: GridPosition, copying: Bool) {
        draggedPosition = source
        guard !isLocked, selectedPositions.contains(source), selectedPositions.count > 1 else {
            clearDragPreview()
            return
        }
        let moving = selectedFilledPositions
        let columnShift = target.column - source.column
        let rowShift = target.row - source.row
        let cells = moving
            .map { GridPosition(column: $0.column + columnShift, row: $0.row + rowShift) }
            .filter(\.isValid)
        let allowed =
            (columnShift != 0 || rowShift != 0)
            && Self.blockPlan(
                in: currentGrid, moving: moving, columnShift: columnShift, rowShift: rowShift, copying: copying) != nil
        let preview = DropPreview(positions: Set(cells), isAllowed: allowed, isCopy: copying)
        if dragPreview != preview { dragPreview = preview }
    }

    public func clearDragPreview() {
        if dragPreview != nil { dragPreview = nil }
    }

    /// Fin du glisser (dépôt ou sortie) : plus d'aperçu.
    public func endDrag() {
        draggedPosition = nil
        clearDragPreview()
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
            var grid = show.adaptingNewGrid(.empty(name: name))  // colonnes lumière communes, si l'option est active
            grid.lightChannel = show.firstFreeLightChannel()  // nil au-delà de 16 : « Sans canal »
            show.grids.append(grid)
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

    /// Change le canal LightKey d'une grille (`nil` = « Sans canal »). Refusé verrouillé, hors de 1…16, ou si une autre
    /// grille utilise déjà ce canal. Les appairages de la grille sont à refaire dans LightKey (l'interface le dit avant).
    public func setLightChannel(grid index: Int, channel: Int?) {
        commit("Canal LightKey") { show, _ in
            guard show.grids.indices.contains(index) else { return false }
            if let channel {
                guard Show.lightChannels.contains(channel), show.sharedLight?.channel != channel,
                    !show.grids.indices.contains(where: { $0 != index && show.grids[$0].lightChannel == channel })
                else { return false }
            }
            show.grids[index].lightChannel = channel
            return true
        }
    }

    // MARK: - Colonnes lumière communes (fiche 01b)

    /// Active ou désactive l'option « Colonnes lumière communes à toutes les grilles ». Activer part de la grille affichée
    /// (ses colonnes lumière deviennent communes, le reste est mis de côté) ; désactiver rend à chaque grille ses colonnes.
    /// Une seule annulation ; refusé verrouillé ; aucun son n'est arrêté.
    public func setSharedLight(_ enabled: Bool) {
        commit(enabled ? "Colonnes lumière communes" : "Colonnes lumière propres à chaque grille") { show, grid in
            if enabled { return show.enableSharedLight(fromGrid: grid) }
            guard show.sharedLight != nil else { return false }
            show.disableSharedLight()
            return true
        }
    }

    /// Change le canal LightKey des colonnes communes (refusé s'il est pris par une grille, ou verrouillé).
    public func setSharedLightChannel(_ channel: Int) {
        commit("Canal des colonnes communes") { show, _ in show.setSharedLightChannel(channel) }
    }

    // MARK: - Types de colonnes et de pads (fiche 06)

    /// Ce que coûterait le passage d'une colonne de la grille affichée à ce type (pour la feuille de confirmation).
    public func conversionPlan(column: Int, to kind: ColumnKind) -> ConversionPlan {
        guard (0..<PadGrid.size).contains(column) else { return ConversionPlan() }
        return .column(currentGrid.columns[column], to: kind)
    }

    /// Ce que coûterait le passage d'un pad de la grille affichée à ce type (case vide : rien).
    public func conversionPlan(padAt position: GridPosition, to kind: PadKind) -> ConversionPlan {
        guard let pad = pad(at: position) else { return ConversionPlan() }
        return .pad(pad, to: kind)
    }

    /// Pourquoi ce changement de type de colonne est impossible (`nil` s'il est permis). Le verrou est géré à part.
    ///
    /// Colonnes lumière communes (fiche 01b) : une colonne commune ne change pas de type et aucune colonne ne devient
    /// « Lumière » tant que l'option est active, car cela vaudrait pour toutes les grilles (règle 5 de la fiche 01b, **reportée** :
    /// il faut d'abord désactiver l'option, dans Spectacle › Réglages du spectacle…).
    public func columnKindProblem(_ column: Int, to kind: ColumnKind) -> String? {
        guard (0..<PadGrid.size).contains(column) else { return "Colonne introuvable." }
        let current = currentGrid.columns[column].kind
        guard current != kind, show.sharedLight != nil else { return nil }
        if show.isSharedLightColumn(column) {
            return "Cette colonne est commune à toutes les grilles : désactivez les colonnes lumière communes (Spectacle › Réglages du spectacle…) pour changer son type."
        }
        if kind == .light {
            return "Les colonnes lumière sont communes à toutes les grilles : désactivez les colonnes lumière communes (Spectacle › Réglages du spectacle…) pour en ajouter une."
        }
        return nil
    }

    /// Change le type d'une colonne de la grille affichée (son, lumière, son et lumière). Élargir ne retire rien ; restreindre
    /// retire ce qui ne rentre plus (`conversionPlan`, à montrer avant). Une seule annulation, refusé verrouillé, sans effet si le
    /// type est déjà le bon. Aucun autre son ne s'arrête ; un pad qui perd son son s'arrête (le moteur coupe sa voix, comme
    /// quand on supprime un pad).
    @discardableResult
    public func setColumnKind(_ column: Int, to kind: ColumnKind) -> Bool {
        if let problem = columnKindProblem(column, to: kind) {
            conversionNotice = problem
            return false
        }
        return commit("Type de colonne") { show, grid in
            guard show.grids[grid].columns.indices.contains(column), show.grids[grid].columns[column].kind != kind else { return false }
            show.grids[grid].columns[column] = show.grids[grid].columns[column].converted(to: kind)
            return true
        }
    }

    /// Change le type d'un pad (dans une colonne **mixte** seulement : les autres n'acceptent qu'un type). Une seule annulation,
    /// refusé verrouillé. Un pad qui n'a rien à garder (lumière → son, « en attente de son » → son) disparaît : `conversionPlan`
    /// le dit avant.
    @discardableResult
    public func setPadKind(at position: GridPosition, to kind: PadKind) -> Bool {
        guard position.isValid else { return false }
        guard currentGrid.columns[position.column].kind == .mixed else {
            conversionNotice = currentGrid.columns[position.column].kind == .audio
                ? "La colonne n'accepte que le son. Changez son type pour mélanger."
                : "La colonne n'accepte que la lumière. Changez son type pour mélanger."
            return false
        }
        return commit("Type du pad") { show, grid in
            guard let pad = show.grids[grid][position], pad.kind != kind else { return false }
            show.grids[grid][position] = pad.converted(to: kind)
            return true
        }
    }

    /// « Nouvel appui » de la cue d'un pad son et lumière : n'envoyer la note que si LightKey dit la cue éteinte (`turnOnOnly`), ou à
    /// chaque appui (`toggle`). Une annulation ; refusé verrouillé ; sans effet sur un pad sans son ou sans cue.
    @discardableResult
    public func setLightRetrigger(at position: GridPosition, to value: LightRetrigger) -> Bool {
        commit("Nouvel appui de la lumière") { show, grid in
            guard position.isValid, var pad = show.grids[grid][position], pad.audio != nil, pad.light != nil,
                pad.lightRetrigger != value
            else { return false }
            pad.lightRetrigger = value
            show.grids[grid][position] = pad
            return true
        }
    }

    /// Vide une colonne de la grille affichée (ses 8 cases) : une annulation, refusé verrouillé. La colonne garde son type, son nom, son fader.
    @discardableResult
    public func clearColumn(_ column: Int) -> Bool {
        commit("Vider la colonne") { show, grid in
            guard show.grids[grid].columns.indices.contains(column), show.grids[grid].columns[column].slots.contains(where: { $0 != nil })
            else { return false }
            show.grids[grid].columns[column].slots = Array(repeating: nil, count: PadGrid.size)
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
                    pad?.audio?.fileName == wanted
                }
            }
        }
    }
}
