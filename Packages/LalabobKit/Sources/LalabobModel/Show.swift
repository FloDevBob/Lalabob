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
    /// Version du format de fichier. À incrémenter à chaque changement incompatible, avec une migration à la lecture
    /// (`ShowPackage.decodeMigrating`). 2 : un pad a un son et / ou une cue (`Pad.audio`, `Pad.light`), voir ADR 0008.
    /// Les fichiers de version 1 se lisent et se réécrivent en version 2 ; une ancienne version de l'app ne lit pas la 2.
    /// 3 : grilles Apple Music (`PadGrid.kind`, `ColumnKind.music`, `Pad.music`) ; écrite seulement si le spectacle s'en sert
    /// (`requiredFormatVersion`).
    public static let currentFormatVersion = 3

    public var formatVersion: Int
    public var name: String
    public var grids: [PadGrid]
    /// Option « Colonnes lumière communes à toutes les grilles » (`nil` = désactivée). Voir `SharedLight`.
    public var sharedLight: SharedLight?

    /// Un spectacle construit en mémoire (nouveau, tests) : chaque grille sans canal LightKey en reçoit un, dans l'ordre.
    public init(name: String, grids: [PadGrid]) {
        self.formatVersion = Show.currentFormatVersion
        self.name = name
        self.grids = grids
        assignLightChannels(toGrids: Array(grids.indices.filter { grids[$0].lightChannel == nil }))
        self.formatVersion = requiredFormatVersion
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

    /// Premier canal LightKey qu'aucune grille n'utilise, ni les colonnes communes (`nil` si les 16 sont pris).
    public func firstFreeLightChannel() -> Int? {
        var used = Set(grids.compactMap(\.lightChannel))
        if let shared = sharedLight?.channel { used.insert(shared) }
        return Self.lightChannels.first { !used.contains($0) }
    }

    /// Donne un canal aux grilles `indices`, dans l'ordre : la grille N prend le canal N s'il est libre, sinon le premier
    /// canal libre, sinon aucun (« Sans canal »).
    public mutating func assignLightChannels(toGrids indices: [Int]) {
        for index in indices where grids.indices.contains(index) {
            var used = Set(grids.compactMap(\.lightChannel))
            if let shared = sharedLight?.channel { used.insert(shared) }
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
                    guard var pad = grids[index].columns[c].slots[r], var cue = pad.light, cue.isPaired else { continue }
                    cue.isPaired = false
                    pad.light = cue
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
    /// Grille standard (sons et lumière) ou grille Apple Music. Absent des fichiers = standard.
    public var kind: GridKind
    public var columns: [Column]
    /// Canal MIDI (1 à 16) sur lequel cette grille parle à LightKey : cues, faders lumière et retour d'état.
    /// `nil` = « Sans canal » : la lumière de cette grille n'envoie rien. Gardé quand on réordonne les onglets.
    public var lightChannel: Int?
    /// Colonnes mises de côté pendant que les colonnes lumière sont communes (voir `SharedLight`) ; vide sinon.
    public var parkedColumns: [ParkedColumn]

    public init(
        id: UUID = UUID(), name: String, kind: GridKind = .standard, columns: [Column], lightChannel: Int? = nil,
        parkedColumns: [ParkedColumn] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.columns = columns
        self.lightChannel = lightChannel
        self.parkedColumns = parkedColumns
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind, columns, lightChannel, parkedColumns }

    /// Les fichiers d'avant le canal par grille n'ont pas `lightChannel` : la grille se lit « sans canal » et
    /// `ShowPackage` lui en attribue un (migration). Un canal absent se distingue d'un « Sans canal » écrit (`null`).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decodeIfPresent(GridKind.self, forKey: .kind) ?? .standard
        columns = try container.decode([Column].self, forKey: .columns)
        lightChannel = try container.decodeIfPresent(Int.self, forKey: .lightChannel)
        parkedColumns = try container.decodeIfPresent([ParkedColumn].self, forKey: .parkedColumns) ?? []
    }

    /// `lightChannel` est toujours écrit, `null` compris : un « Sans canal » choisi ne doit pas être pris pour un
    /// ancien fichier à migrer.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        if kind != .standard { try container.encode(kind, forKey: .kind) }
        try container.encode(columns, forKey: .columns)
        try container.encode(lightChannel, forKey: .lightChannel)
        if !parkedColumns.isEmpty { try container.encode(parkedColumns, forKey: .parkedColumns) }
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

/// Le type d'une colonne : ce qu'elle accepte (`accepts`) et ce que porte son fader.
public enum ColumnKind: String, Codable, Sendable {
    /// Sons uniquement : fader de volume, filtre, stop.
    case audio
    /// Cues uniquement : fader MIDI vers LightKey.
    case light
    /// Son et lumière : accepte des pads son, lumière, ou les deux à la fois ; fader de volume.
    case mixed
    /// Morceaux d'Apple Music (grilles Apple Music seulement) : pas de fader (volume général de Music), un bouton stop.
    case music

    /// La colonne a un volume, un filtre, un vumètre et un bouton stop (sons de Lalabob).
    public var hasAudio: Bool { self == .audio || self == .mixed }

    /// La colonne peut porter des cues LightKey (appairage, relais, retour d'état).
    public var hasLight: Bool { self == .light || self == .mixed }

    /// La colonne accepte un pad de ce type : une colonne mixte accepte tout, les autres leur seul type.
    public func accepts(_ pad: PadKind) -> Bool {
        switch self {
        case .mixed: pad != .music
        case .audio: pad == .audio
        case .light: pad == .light
        case .music: pad == .music
        }
    }
}

/// Le type d'un pad, déduit de ses parties (`Pad.kind`).
public enum PadKind: String, Codable, Sendable {
    case audio, light, mixed
    /// Un morceau d'Apple Music (`Pad.music`).
    case music
}

/// Ce que fait un nouvel appui sur un pad « son et lumière » dont la cue est déjà allumée dans LightKey (fiche 06).
/// LightKey bascule la cue à chaque note reçue : relancer le son ne doit pas l'éteindre.
public enum LightRetrigger: String, Codable, Sendable {
    /// N'envoyer la note que si LightKey dit la cue éteinte ou inconnue (défaut).
    case turnOnOnly
    /// Envoyer la note à chaque appui, comme un pad lumière.
    case toggle
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
        Column(name: name, kind: kind, level: kind.hasAudio ? 0.8 : 1, slots: Array(repeating: nil, count: PadGrid.size))
    }
}

/// Un pad : ce qu'une touche du contrôleur déclenche.
///
/// Un pad a un son (`audio`), une cue lumière (`light`), ou les deux (« son et lumière »). Au moins une partie : un pad sans
/// rien est refusé par `Show.validate()`.
public struct Pad: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var tint: Tint
    public var ledIntensity: LEDIntensity
    /// Le son du pad et ses réglages de lecture.
    public var audio: AudioClip?
    /// La cue envoyée à LightKey.
    public var light: LightCue?
    /// « Son et lumière » choisi sans que le son soit encore déposé : le pad ne joue que sa cue en attendant. Seulement avec `light`.
    public var awaitsSound: Bool
    /// Nouvel appui d'un pad son et lumière : voir `LightRetrigger`.
    public var lightRetrigger: LightRetrigger
    /// Un morceau d'Apple Music (grilles Apple Music) : exclusif, un pad Music n'a ni son ni cue.
    public var music: MusicTrackRef?

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String = "",
        tint: Tint,
        ledIntensity: LEDIntensity = .full,
        audio: AudioClip? = nil,
        light: LightCue? = nil,
        awaitsSound: Bool = false,
        lightRetrigger: LightRetrigger = .turnOnOnly,
        music: MusicTrackRef? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.ledIntensity = ledIntensity
        self.audio = audio
        self.light = light
        self.awaitsSound = awaitsSound
        self.lightRetrigger = lightRetrigger
        self.music = music
    }

    /// Un pad Apple Music : titre et sous-titre pris du morceau.
    public static func track(_ track: MusicTrackRef, tint: Tint, id: UUID = UUID()) -> Pad {
        Pad(id: id, title: String(track.title.prefix(80)), subtitle: String(track.artist.prefix(80)), tint: tint, music: track)
    }

    /// Un pad son.
    public static func sound(
        id: UUID = UUID(), title: String, subtitle: String = "", tint: Tint, ledIntensity: LEDIntensity = .full, clip: AudioClip
    ) -> Pad {
        Pad(id: id, title: title, subtitle: subtitle, tint: tint, ledIntensity: ledIntensity, audio: clip)
    }

    /// Un pad lumière.
    public static func cue(
        id: UUID = UUID(), title: String, subtitle: String = "", tint: Tint, ledIntensity: LEDIntensity = .full, cue: LightCue
    ) -> Pad {
        Pad(id: id, title: title, subtitle: subtitle, tint: tint, ledIntensity: ledIntensity, light: cue)
    }

    /// Son, lumière, ou les deux : déduit des parties. « En attente de son » compte comme un pad mixte.
    public var kind: PadKind {
        if music != nil { return .music }
        if audio != nil, light != nil { return .mixed }
        if light != nil { return awaitsSound ? .mixed : .light }
        return .audio
    }

    /// Copie avec un nouvel identifiant (duplication, ⌥-glisser, coller).
    public func duplicated() -> Pad {
        var copy = self
        copy.id = UUID()
        return copy
    }
}

// MARK: - Lecture et écriture d'un pad (format versions 1 et 2)

extension Pad: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, tint, ledIntensity
        case audio, light, awaitsSound, lightRetrigger, music
        /// Version 1 : `content` = `{"audio": {"clip": …}}` ou `{"light": {"cue": …}}`.
        case content
    }

    private enum LegacyContentKeys: String, CodingKey { case audio, light }
    private struct LegacyAudio: Decodable { let clip: AudioClip }
    private struct LegacyLight: Decodable { let cue: LightCue }

    /// Version 2 : `audio` et `light` à plat, facultatifs. Version 1 : `content`, converti ici (un pad son devient un pad avec
    /// `audio`, un pad lumière un pad avec `light`). Les deux formes mêlées, ou un `content` vide, sont refusés.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        tint = try container.decode(Tint.self, forKey: .tint)
        ledIntensity = try container.decode(LEDIntensity.self, forKey: .ledIntensity)
        awaitsSound = try container.decodeIfPresent(Bool.self, forKey: .awaitsSound) ?? false
        lightRetrigger = try container.decodeIfPresent(LightRetrigger.self, forKey: .lightRetrigger) ?? .turnOnOnly
        music = try container.decodeIfPresent(MusicTrackRef.self, forKey: .music)

        if container.contains(.content) {
            guard !container.contains(.audio), !container.contains(.light) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .content, in: container, debugDescription: "Un pad ne peut pas avoir à la fois « content » (version 1) et « audio » / « light » (version 2).")
            }
            let legacy = try container.nestedContainer(keyedBy: LegacyContentKeys.self, forKey: .content)
            if legacy.contains(.audio) {
                audio = try legacy.decode(LegacyAudio.self, forKey: .audio).clip
                light = nil
            } else if legacy.contains(.light) {
                audio = nil
                light = try legacy.decode(LegacyLight.self, forKey: .light).cue
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .content, in: container, debugDescription: "« content » ne contient ni son ni lumière.")
            }
        } else {
            audio = try container.decodeIfPresent(AudioClip.self, forKey: .audio)
            light = try container.decodeIfPresent(LightCue.self, forKey: .light)
        }
    }

    /// Toujours la version 2 ; les valeurs par défaut (`awaitsSound` faux, `lightRetrigger` « allumer seulement ») ne sont pas écrites.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(tint, forKey: .tint)
        try container.encode(ledIntensity, forKey: .ledIntensity)
        try container.encodeIfPresent(audio, forKey: .audio)
        try container.encodeIfPresent(light, forKey: .light)
        if awaitsSound { try container.encode(true, forKey: .awaitsSound) }
        if lightRetrigger != .turnOnOnly { try container.encode(lightRetrigger, forKey: .lightRetrigger) }
        try container.encodeIfPresent(music, forKey: .music)
    }
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
