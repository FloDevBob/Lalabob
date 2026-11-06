import Foundation

/// Ce qui peut empêcher la lecture d'un Live Set Ableton.
public enum AbletonImportError: Error, Equatable, Sendable {
    /// Le fichier n'est pas compressé en gzip (un `.als` l'est toujours).
    case notAGzipFile
    case corruptArchive
    /// Fichier ou XML démesuré : refusé avant lecture complète.
    case tooLarge
    case unreadableXML
    /// XML valide, mais pas un Live Set (pas de `<LiveSet>`).
    case notALiveSet
    case cannotRead
    case noLiveSetInFolder
    case severalLiveSetsInFolder([String])
}

extension AbletonImportError {
    /// Message pour l'interface.
    public var message: String {
        switch self {
        case .notAGzipFile, .notALiveSet: "Ce fichier n'est pas un Live Set Ableton (.als)."
        case .corruptArchive, .unreadableXML: "Ce Live Set est illisible ou abîmé."
        case .tooLarge: "Ce Live Set est anormalement gros ; il n'a pas été ouvert."
        case .cannotRead: "Le fichier n'a pas pu être lu."
        case .noLiveSetInFolder: "Aucun Live Set (.als) dans ce dossier."
        case .severalLiveSetsInFolder(let names):
            "Plusieurs Live Sets dans ce dossier (" + names.joined(separator: ", ") + ") : choisissez directement le fichier .als."
        }
    }
}

/// Ce que Lalabob lit d'un Live Set (Live 12) : les clips **audio** de la vue Session.
/// Tout le reste (pistes MIDI, retours, arrangement, effets, automations) est ignoré.
public struct AbletonLiveSet: Equatable, Sendable {
    /// Attribut `Creator` de la racine, par exemple « Ableton Live 12.1.5 Suite ».
    public var creator: String = ""
    /// Nombre de scènes déclarées (lignes de la vue Session).
    public var sceneCount: Int = 0
    /// Pistes audio, dans l'ordre de la vue Session (de gauche à droite).
    public var audioTracks: [AbletonAudioTrack] = []
    public var ignoredMidiTrackCount: Int = 0

    public init() {}

    /// Nombre de scènes jusqu'au dernier clip trouvé (au moins 1).
    public var usedSceneCount: Int {
        let last = audioTracks.flatMap { $0.clips.keys }.max() ?? -1
        return max(last + 1, 1)
    }

    public var clipCount: Int { audioTracks.reduce(0) { $0 + $1.clips.count } }
}

public struct AbletonAudioTrack: Equatable, Sendable {
    public var name: String
    /// Clips de la vue Session, par indice de scène (0 = première scène).
    public var clips: [Int: AbletonClip]

    public init(name: String, clips: [Int: AbletonClip]) {
        self.name = name
        self.clips = clips
    }
}

public struct AbletonClip: Equatable, Sendable {
    public var name: String
    /// Interrupteur « Loop » du clip.
    public var loops: Bool
    /// `nil` : le clip n'a pas de fichier son identifiable.
    public var sample: AbletonSampleReference?
    /// Début de la partie jouée, en secondes dans le fichier (0 = début du fichier).
    public var trimStart: TimeInterval
    /// Fin de la partie jouée, en secondes ; `nil` = fin du fichier (ou durée inconnue).
    public var trimEnd: TimeInterval?
    /// Volume du clip (« Clip Gain » de Live), en décibels.
    public var gainDB: Double

    public init(
        name: String, loops: Bool, sample: AbletonSampleReference?,
        trimStart: TimeInterval = 0, trimEnd: TimeInterval? = nil, gainDB: Double = 0
    ) {
        self.name = name
        self.loops = loops
        self.sample = sample
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.gainDB = gainDB
    }
}

/// Où Live a rangé le son d'un clip.
public struct AbletonSampleReference: Equatable, Sendable {
    /// Chemin relatif au dossier du `.als` (`<RelativePath>`), vide si absent.
    public var relativePath: String
    /// Chemin absolu mémorisé par Live (`<Path>`), vide si absent.
    public var absolutePath: String
    /// Nom du fichier (dernier élément du chemin).
    public var fileName: String

    public init(relativePath: String, absolutePath: String, fileName: String) {
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.fileName = fileName
    }
}
