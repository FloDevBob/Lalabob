import Foundation

/// Option « Colonnes lumière communes à toutes les grilles » (fiche 01b, décidée le 25/11/2026).
///
/// Activée, les colonnes de type Lumière de la grille d'origine sont **les mêmes dans toutes les grilles** (cues, faders,
/// appairages) et parlent à LightKey sur un canal commun : changer de grille ne change pas la lumière, on appaire une fois.
///
/// Stockage : chaque grille garde une **copie identique** de chaque colonne commune (à la même position). Ainsi tout le code
/// qui lit une grille (écran, LED, relais, moteur audio) n'a rien de particulier à faire ; c'est l'écriture qui recopie la
/// colonne modifiée dans toutes les grilles (`propagateSharedLight(from:)`). Ce qui occupait ces positions dans les autres
/// grilles, et leurs propres colonnes lumière ailleurs, est **mis de côté** (`PadGrid.parkedColumns`) et revient quand on
/// désactive l'option.
public struct SharedLight: Codable, Sendable, Equatable {
    /// Canal MIDI (1 à 16) des colonnes communes ; aucune grille ne l'utilise pour elle-même.
    public var channel: Int
    /// La grille dont les colonnes lumière sont devenues communes ; elle les reprend quand on désactive l'option.
    public var originGridID: PadGrid.ID
    /// Positions (0 à 7) des colonnes communes, triées.
    public var columnIndices: [Int]

    public init(channel: Int, originGridID: PadGrid.ID, columnIndices: [Int]) {
        self.channel = channel
        self.originGridID = originGridID
        self.columnIndices = columnIndices.sorted()
    }
}

/// Une colonne mise de côté, avec sa position dans la grille.
public struct ParkedColumn: Codable, Sendable, Equatable {
    public var index: Int
    public var column: Column

    public init(index: Int, column: Column) {
        self.index = index
        self.column = column
    }
}

/// Ce que l'activation mettrait de côté dans une grille (pour la feuille de confirmation).
public struct SharedLightParking: Equatable, Sendable {
    public var grid: Int
    /// Positions des colonnes mises de côté, triées.
    public var columns: [Int]
    /// Pads contenus dans ces colonnes (son ou lumière) : ils reviennent si on désactive l'option.
    public var padCount: Int
}

extension Show {
    /// L'option est-elle active pour cette position de colonne ?
    public func isSharedLightColumn(_ index: Int) -> Bool {
        sharedLight?.columnIndices.contains(index) ?? false
    }

    /// Canal LightKey d'une colonne de la grille `grid` : le canal commun pour une colonne commune, sinon celui de la grille.
    public func lightChannel(grid: Int, column: Int) -> Int? {
        if let sharedLight, sharedLight.columnIndices.contains(column) { return sharedLight.channel }
        return grids.indices.contains(grid) ? grids[grid].lightChannel : nil
    }

    /// Positions des colonnes lumière d'une grille.
    func lightColumnIndices(ofGrid grid: Int) -> [Int] {
        grids[grid].columns.indices.filter { grids[grid].columns[$0].kind == .light }
    }

    /// Ce que l'activation depuis la grille `origin` mettrait de côté, grille par grille (les grilles sans rien à mettre de
    /// côté sont omises). Vide si l'activation est impossible.
    public func sharedLightParkingPreview(fromGrid origin: Int) -> [SharedLightParking] {
        guard grids.indices.contains(origin) else { return [] }
        let shared = Set(lightColumnIndices(ofGrid: origin))
        guard !shared.isEmpty else { return [] }
        return grids.indices.compactMap { g in
            guard g != origin else { return nil }
            let parked = grids[g].columns.indices.filter { shared.contains($0) || grids[g].columns[$0].kind == .light }
            guard !parked.isEmpty else { return nil }
            let pads = parked.reduce(0) { $0 + grids[g].columns[$1].slots.compactMap { $0 }.count }
            return SharedLightParking(grid: g, columns: parked, padCount: pads)
        }
    }

    /// Pourquoi l'activation depuis `origin` est impossible (`nil` si elle est possible).
    public func sharedLightActivationProblem(fromGrid origin: Int) -> String? {
        guard sharedLight == nil else { return "Les colonnes lumière sont déjà communes." }
        guard grids.indices.contains(origin) else { return "Grille introuvable." }
        guard !lightColumnIndices(ofGrid: origin).isEmpty else { return "La grille affichée n'a aucune colonne lumière." }
        guard grids[origin].lightChannel != nil || firstFreeLightChannel() != nil else {
            return "Les 16 canaux des lumières sont déjà pris par des grilles."
        }
        return nil
    }

    /// Active l'option depuis la grille `origin` (règles 3 et 6 de la fiche 01b). Renvoie `false` sans rien changer si
    /// c'est impossible (`sharedLightActivationProblem`).
    @discardableResult
    public mutating func enableSharedLight(fromGrid origin: Int) -> Bool {
        guard sharedLightActivationProblem(fromGrid: origin) == nil else { return false }
        let indices = lightColumnIndices(ofGrid: origin)
        // Le canal commun est celui de la grille d'origine : ses appairages restent valables. Elle en prend un autre.
        guard let channel = grids[origin].lightChannel ?? firstFreeLightChannel() else { return false }
        grids[origin].lightChannel = nil
        sharedLight = SharedLight(channel: channel, originGridID: grids[origin].id, columnIndices: indices)
        grids[origin].lightChannel = firstFreeLightChannel()  // le canal commun est exclu ; nil si plus rien de libre

        let shared = Set(indices)
        for g in grids.indices where g != origin {
            for c in grids[g].columns.indices {
                if shared.contains(c) {
                    grids[g].parkedColumns.append(ParkedColumn(index: c, column: grids[g].columns[c]))
                    grids[g].columns[c] = grids[origin].columns[c]
                } else if grids[g].columns[c].kind == .light {
                    // Option active, le type Lumière vaut pour toutes les grilles : cette colonne attend son retour.
                    grids[g].parkedColumns.append(ParkedColumn(index: c, column: grids[g].columns[c]))
                    grids[g].columns[c] = Column.empty(name: grids[g].columns[c].name, kind: grids[g].kind.contentColumn)
                }
            }
        }
        return true
    }

    /// Désactive l'option (règle 4) : la grille d'origine garde les colonnes communes (avec les modifications faites
    /// entre-temps) et retrouve son canal ; les autres grilles retrouvent leurs colonnes mises de côté. Une grille ajoutée
    /// pendant que l'option était active garde une copie des colonnes communes, non appairée (elle a son propre canal).
    public mutating func disableSharedLight() {
        guard let sharedLight else { return }
        let origin = grids.firstIndex { $0.id == sharedLight.originGridID } ?? 0
        let shared = Set(sharedLight.columnIndices)
        for g in grids.indices where g != origin {
            let parked = grids[g].parkedColumns
            for item in parked where grids[g].columns.indices.contains(item.index) {
                grids[g].columns[item.index] = item.column
            }
            let restored = Set(parked.map(\.index))
            for c in shared.subtracting(restored) where grids[g].columns.indices.contains(c) {
                grids[g].columns[c] = grids[g].columns[c].withoutPairings()
            }
            grids[g].parkedColumns = []
        }
        self.sharedLight = nil
        // La grille d'origine prend le canal commun (aucune grille ne l'utilise) : les appairages des colonnes communes,
        // faits sur ce canal, restent valables. Son canal provisoire se libère.
        grids[origin].lightChannel = sharedLight.channel
    }

    /// Recopie les colonnes communes de la grille `source` dans toutes les autres grilles (après une modification).
    public mutating func propagateSharedLight(from source: Int) {
        guard let sharedLight, grids.indices.contains(source) else { return }
        for c in sharedLight.columnIndices where grids[source].columns.indices.contains(c) {
            let column = grids[source].columns[c]
            for g in grids.indices where g != source { grids[g].columns[c] = column }
        }
    }

    /// Prépare une grille neuve pour ce spectacle : copies des colonnes communes ; ses autres colonnes lumière deviennent
    /// des colonnes son, ou Music dans une grille Apple Music (option active, le type Lumière vaut pour toutes les grilles).
    public func adaptingNewGrid(_ grid: PadGrid) -> PadGrid {
        guard let sharedLight, let model = grids.first else { return grid }
        var grid = grid
        for c in grid.columns.indices {
            if sharedLight.columnIndices.contains(c) {
                grid.columns[c] = model.columns[c]
            } else if grid.columns[c].kind == .light {
                grid.columns[c] = Column.empty(name: grid.columns[c].name, kind: grid.kind.contentColumn)
            }
        }
        return grid
    }

    /// Change le canal commun. Refusé (`false`) hors de 1…16 ou si une grille l'utilise.
    @discardableResult
    public mutating func setSharedLightChannel(_ channel: Int) -> Bool {
        guard sharedLight != nil, Self.lightChannels.contains(channel),
            !grids.contains(where: { $0.lightChannel == channel })
        else { return false }
        sharedLight?.channel = channel
        return true
    }
}

extension Column {
    /// La même colonne, sans aucun appairage (cues et fader).
    func withoutPairings() -> Column {
        var column = self
        column.isFaderPaired = false
        for r in column.slots.indices {
            guard var pad = column.slots[r], var cue = pad.light, cue.isPaired else { continue }
            cue.isPaired = false
            pad.light = cue
            column.slots[r] = pad
        }
        return column
    }
}
