import Foundation

/// Position d'une case dans la grille 8×8. `row` 0 = rangée du haut, `column` 0 = colonne de gauche.
public struct GridPosition: Hashable, Codable, Sendable, CustomStringConvertible {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }

    public var isValid: Bool { (0..<PadGrid.size).contains(column) && (0..<PadGrid.size).contains(row) }

    public var description: String { "(\(column), \(row))" }

    /// Toutes les positions, colonne par colonne, de haut en bas.
    public static var all: [GridPosition] {
        (0..<PadGrid.size).flatMap { c in (0..<PadGrid.size).map { r in GridPosition(column: c, row: r) } }
    }
}

/// Un spectacle : le contenu d'un document `.lalabob`.
public struct Show: Codable, Sendable, Equatable {
    /// Version du format de fichier. À incrémenter à chaque changement incompatible,
    /// avec une migration dans `ShowMigration`.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var name: String
    public var grids: [PadGrid]

    /// Un spectacle construit en mémoire (nouveau, tests) : chaque grille sans canal LightKey en reçoit un, dans l'ordre.
    public init(name: String, grids: [PadGrid]) {
        self.formatVersion = Show.currentFormatVersion
        self.name = name
        self.grids = grids
        assignLightChannels(toGrids: Array(grids.indices.filter { grids[$0].lightChannel == nil }))
    }

    /// Un spectacle neuf avec une grille vide.
    public static func new(name: String = "Nouveau spectacle") -> Show {
        Show(name: name, grids: [.empty(name: "Grille 1")])
    }
}

// MARK: - Canal LightKey par grille

extension Show {
    /// Canaux MIDI possibles pour LightKey.
    public static let lightChannels = 1...16

    /// Premier canal LightKey qu'aucune grille n'utilise (`nil` si les 16 sont pris).
    public func firstFreeLightChannel() -> Int? {
        let used = Set(grids.compactMap(\.lightChannel))
        return Self.lightChannels.first { !used.contains($0) }
    }

    /// Donne un canal aux grilles `indices`, dans l'ordre : la grille N prend le canal N s'il est libre, sinon le premier
    /// canal libre, sinon aucun (« Sans canal »).
    public mutating func assignLightChannels(toGrids indices: [Int]) {
        for index in indices where grids.indices.contains(index) {
            let used = Set(grids.compactMap(\.lightChannel))
            let preferred = index + 1
            if Self.lightChannels.contains(preferred), !used.contains(preferred) {
                grids[index].lightChannel = preferred
            } else {
                grids[index].lightChannel = firstFreeLightChannel()
            }
        }
    }

    /// Migration d'un fichier d'avant le canal par grille (`indices` : les grilles lues sans canal). Jusque-là tout
    /// partait sur le canal 1 : les cues et faders lumière appairés des grilles 2 et suivantes étaient en réalité ceux de
    /// la grille 1 dans LightKey. Ils sont marqués non appairés. Renvoie les index des grilles où un appairage a été retiré.
    public mutating func migrateToLightChannelPerGrid(gridsWithoutChannel indices: [Int]) -> [Int] {
        assignLightChannels(toGrids: indices)
        var reset: [Int] = []
        for index in indices where index > 0 && grids.indices.contains(index) {
            var changed = false
            for c in grids[index].columns.indices {
                if grids[index].columns[c].isFaderPaired {
                    grids[index].columns[c].isFaderPaired = false
                    changed = true
                }
                for r in grids[index].columns[c].slots.indices {
                    guard var pad = grids[index].columns[c].slots[r], case .light(var cue) = pad.content, cue.isPaired
                    else { continue }
                    cue.isPaired = false
                    pad.content = .light(cue: cue)
                    grids[index].columns[c].slots[r] = pad
                    changed = true
                }
            }
            if changed { reset.append(index) }
        }
        return reset
    }
}

/// Une grille : une « programmation » complète du contrôleur, 8 colonnes de 8 cases.
public struct PadGrid: Codable, Sendable, Equatable, Identifiable {
    public static let size = 8
    /// Colonnes réservées à la lumière par défaut (les deux de droite).
    public static let defaultLightColumns: Set<Int> = [6, 7]

    public var id: UUID
    public var name: String
    public var columns: [Column]
    /// Canal MIDI (1 à 16) sur lequel cette grille parle à LightKey : cues, faders lumière et retour d'état.
    /// `nil` = « Sans canal » : la lumière de cette grille n'envoie rien. Gardé quand on réordonne les onglets.
    public var lightChannel: Int?

    public init(id: UUID = UUID(), name: String, columns: [Column], lightChannel: Int? = nil) {
        self.id = id
        self.name = name
        self.columns = columns
        self.lightChannel = lightChannel
    }

    private enum CodingKeys: String, CodingKey { case id, name, columns, lightChannel }

    /// Les fichiers d'avant le canal par grille n'ont pas `lightChannel` : la grille se lit « sans canal » et
    /// `ShowPackage` lui en attribue un (migration). Un canal absent se distingue d'un « Sans canal » écrit (`null`).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        columns = try container.decode([Column].self, forKey: .columns)
        lightChannel = try container.decodeIfPresent(Int.self, forKey: .lightChannel)
    }

    /// `lightChannel` est toujours écrit, `null` compris : un « Sans canal » choisi ne doit pas être pris pour un
    /// ancien fichier à migrer.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(columns, forKey: .columns)
        try container.encode(lightChannel, forKey: .lightChannel)
    }

    public static func empty(name: String) -> PadGrid {
        PadGrid(
            name: name,
            columns: (0..<size).map { index in
                Column.empty(
                    name: "Colonne \(index + 1)",
                    kind: defaultLightColumns.contains(index) ? .light : .audio
                )
            }
        )
    }

    public subscript(position: GridPosition) -> Pad? {
        get { columns[position.column].slots[position.row] }
        set { columns[position.column].slots[position.row] = newValue }
    }
}

public enum ColumnKind: String, Codable, Sendable {
    case audio, light
}

/// Une colonne de 8 cases, avec son fader (volume pour l'audio, intensité pour la lumière).
public struct Column: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: ColumnKind
    /// Niveau du fader, de 0 à 1.
    public var level: Double
    /// Exactement `PadGrid.size` cases ; `nil` = case vide.
    public var slots: [Pad?]
    /// Colonne lumière : son fader a été appairé à un réglage de LightKey (mode « Appairage lumière »).
    public var isFaderPaired: Bool
    /// Filtre DJ de la colonne son (`FilterCurve`), de −1 (passe-bas) à +1 (passe-haut) ; 0 = neutre, son intact.
    public var filter: Double

    public init(
        id: UUID = UUID(), name: String, kind: ColumnKind, level: Double = 0.8, slots: [Pad?], isFaderPaired: Bool = false,
        filter: Double = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.level = level
        self.slots = slots
        self.isFaderPaired = isFaderPaired
        self.filter = filter
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind, level, slots, isFaderPaired, filter }

    /// Les spectacles d'avant l'appairage des faders n'ont pas `isFaderPaired` : ils s'ouvrent non appairés.
    /// Ceux d'avant le filtre de colonne n'ont pas `filter` : ils s'ouvrent au neutre.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(ColumnKind.self, forKey: .kind)
        level = try container.decode(Double.self, forKey: .level)
        slots = try container.decode([Pad?].self, forKey: .slots)
        isFaderPaired = try container.decodeIfPresent(Bool.self, forKey: .isFaderPaired) ?? false
        filter = try container.decodeIfPresent(Double.self, forKey: .filter) ?? 0
    }

    public static func empty(name: String, kind: ColumnKind) -> Column {
        Column(name: name, kind: kind, level: kind == .audio ? 0.8 : 1, slots: Array(repeating: nil, count: PadGrid.size))
    }
}

/// Un pad : ce qu'une touche du contrôleur déclenche.
public struct Pad: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var tint: Tint
    public var ledIntensity: LEDIntensity
    public var content: PadContent

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String = "",
        tint: Tint,
        ledIntensity: LEDIntensity = .full,
        content: PadContent
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.ledIntensity = ledIntensity
        self.content = content
    }

    public var kind: ColumnKind {
        switch content {
        case .audio: .audio
        case .light: .light
        }
    }

    /// Copie avec un nouvel identifiant (duplication, ⌥-glisser, coller).
    public func duplicated() -> Pad {
        var copy = self
        copy.id = UUID()
        return copy
    }
}

public enum PadContent: Codable, Sendable, Equatable {
    case audio(clip: AudioClip)
    case light(cue: LightCue)
}

/// Un extrait audio et ses réglages de lecture.
public struct AudioClip: Codable, Sendable, Equatable {
    /// Nom du fichier dans le dossier `Audio/` du document. Jamais un chemin.
    public var fileName: String
    /// Début de l'élagage, en secondes.
    public var trimStart: TimeInterval
    /// Fin de l'élagage, en secondes ; `nil` = fin du fichier.
    public var trimEnd: TimeInterval?
    public var fadeIn: TimeInterval?
    public var fadeOut: TimeInterval?
    public var loops: Bool
    public var retrigger: RetriggerBehavior
    /// Gain propre au pad, en décibels.
    public var gainDB: Double

    public init(
        fileName: String,
        trimStart: TimeInterval = 0,
        trimEnd: TimeInterval? = nil,
        fadeIn: TimeInterval? = nil,
        fadeOut: TimeInterval? = nil,
        loops: Bool = false,
        retrigger: RetriggerBehavior = .restart,
        gainDB: Double = 0
    ) {
        self.fileName = fileName
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.loops = loops
        self.retrigger = retrigger
        self.gainDB = gainDB
    }
}

/// Ce que fait un nouvel appui sur un pad qui joue déjà.
/// (Un appui sur un pad en pause reprend toujours la lecture.)
public enum RetriggerBehavior: String, Codable, Sendable {
    case restart, stop
}

/// Une commande lumière : le message MIDI envoyé vers le logiciel lumière (LightKey).
public struct LightCue: Codable, Sendable, Equatable {
    public var output: MIDIMessageSpec
    public var behavior: LightBehavior
    /// Le logiciel lumière peut renvoyer l'état pour allumer la LED.
    public var ledFeedback: Bool
    /// La cue a été appairée à une cue de LightKey (mode « Appairage lumière », ADR 0006). Sert à repérer, en mode
    /// d'appairage, les cases libres ; LightKey seul sait vraiment ce qu'il y a derrière la note.
    public var isPaired: Bool

    public init(output: MIDIMessageSpec, behavior: LightBehavior = .impulse, ledFeedback: Bool = true, isPaired: Bool = false) {
        self.output = output
        self.behavior = behavior
        self.ledFeedback = ledFeedback
        self.isPaired = isPaired
    }

    private enum CodingKeys: String, CodingKey { case output, behavior, ledFeedback, isPaired }

    /// Les spectacles enregistrés avant l'appairage n'ont pas `isPaired` : ils s'ouvrent comme non appairés.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        output = try container.decode(MIDIMessageSpec.self, forKey: .output)
        behavior = try container.decode(LightBehavior.self, forKey: .behavior)
        ledFeedback = try container.decode(Bool.self, forKey: .ledFeedback)
        isPaired = try container.decodeIfPresent(Bool.self, forKey: .isPaired) ?? false
    }
}

public enum LightBehavior: String, Codable, Sendable {
    /// Un appui envoie la commande une fois.
    case impulse
    /// Premier appui ON, second appui OFF.
    case toggle
    /// Actif tant que le pad est enfoncé.
    case momentary
}

/// Description d'un message MIDI sortant, indépendante de CoreMIDI.
public struct MIDIMessageSpec: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case note, controlChange
    }

    public var kind: Kind
    /// Canal MIDI, de 0 à 15 (affiché 1 à 16).
    public var channel: UInt8
    /// Numéro de note ou de contrôleur, de 0 à 127.
    public var number: UInt8
    /// Vélocité ou valeur « ON », de 0 à 127.
    public var value: UInt8

    public init(kind: Kind, channel: UInt8, number: UInt8, value: UInt8 = 127) {
        self.kind = kind
        self.channel = channel
        self.number = number
        self.value = value
    }
}
