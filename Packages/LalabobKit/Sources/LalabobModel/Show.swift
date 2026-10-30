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

    public init(name: String, grids: [PadGrid]) {
        self.formatVersion = Show.currentFormatVersion
        self.name = name
        self.grids = grids
    }

    /// Un spectacle neuf avec une grille vide.
    public static func new(name: String = "Nouveau spectacle") -> Show {
        Show(name: name, grids: [.empty(name: "Grille 1")])
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

    public init(id: UUID = UUID(), name: String, columns: [Column]) {
        self.id = id
        self.name = name
        self.columns = columns
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

    public init(id: UUID = UUID(), name: String, kind: ColumnKind, level: Double = 0.8, slots: [Pad?]) {
        self.id = id
        self.name = name
        self.kind = kind
        self.level = level
        self.slots = slots
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

    public init(output: MIDIMessageSpec, behavior: LightBehavior = .impulse, ledFeedback: Bool = true) {
        self.output = output
        self.behavior = behavior
        self.ledFeedback = ledFeedback
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
