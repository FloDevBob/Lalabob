import AppKit
import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobDMX
import LalabobModel
import Observation

// Fenêtre d'accueil (spec `docs/spec-fenetre-accueil.md`) : l'état du matériel et les spectacles récents.
// Les textes vivent ici, dans un modèle pur (`WelcomeChecklist`) : c'est lui que les tests couvrent.

// MARK: - Faits

/// Où sort le son de Lalabob, vu de la fenêtre d'accueil.
public enum AudioOutputKind: Equatable, Sendable {
    /// Les haut-parleurs du Mac : le son ne va pas dans la salle.
    case builtInSpeakers
    /// La prise casque (mini-jack) du Mac : là où se branche l'enceinte.
    case headphoneJack
    /// Une autre sortie (carte son USB, AirPlay, Bluetooth…).
    case other

    /// `kAudioDeviceTransportTypeBuiltIn` (« bltn »).
    static let builtInTransport: UInt32 = 0x626C_746E
    /// Source « ispk » (haut-parleurs intégrés).
    static let speakerSource: UInt32 = 0x6973_706B
    /// Source « hdpn » (prise casque).
    static let headphoneSource: UInt32 = 0x6864_706E

    /// Relevé sur un MacBook Pro (Apple Silicon, macOS 26) : « Haut-parleurs MacBook Pro », transport « bltn », source
    /// « ispk », identifiant `BuiltInSpeakerDevice`. La prise casque est un autre périphérique intégré (source « hdpn »,
    /// identifiant `BuiltInHeadphoneOutputDevice`). Seule une sortie intégrée peut être l'un ou l'autre.
    public static func classify(uid: String, name: String, transportType: UInt32, dataSource: UInt32?) -> AudioOutputKind {
        guard transportType == builtInTransport else { return .other }
        if dataSource == headphoneSource { return .headphoneJack }
        if dataSource == speakerSource { return .builtInSpeakers }
        let text = (uid + " " + name).lowercased()
        if ["headphone", "écouteur", "casque"].contains(where: text.contains) { return .headphoneJack }
        if ["speaker", "haut-parleur"].contains(where: text.contains) { return .builtInSpeakers }
        return .other
    }
}

public struct SoundOutputFact: Equatable, Sendable {
    public var name: String
    public var kind: AudioOutputKind

    public init(name: String, kind: AudioOutputKind) {
        self.name = name
        self.kind = kind
    }
}

/// LightKey sur ce Mac. « Ouvert » ne dit pas qu'il écoute « Lalabob Lumière » (ADR 0006) : on n'en prétend pas plus.
public enum LightKeyState: Equatable, Sendable {
    case notInstalled, closed, running
}

/// Ce que Lalabob sait du matériel à un instant donné.
public struct HardwareFacts: Equatable, Sendable {
    public var output: SoundOutputFact?
    public var controller: ControllerModel?
    public var dmxBox: Bool
    public var lightKey: LightKeyState

    public init(output: SoundOutputFact?, controller: ControllerModel?, dmxBox: Bool, lightKey: LightKeyState) {
        self.output = output
        self.controller = controller
        self.dmxBox = dmxBox
        self.lightKey = lightKey
    }
}

// MARK: - Textes

/// « Avant de jouer » : une ligne par appareil, dont les textes suivent l'état en cours. Prêt : ce qui est détecté ;
/// pas prêt : une phrase qui dit ce qui manque et quoi faire. Jamais la liste de toutes les possibilités.
public struct WelcomeChecklist: Equatable, Sendable {
    public enum Device: Equatable, Sendable {
        case sound, controller, light
    }

    public struct Line: Equatable, Sendable {
        public var device: Device
        public var isReady: Bool
        /// L'étiquette de statut, toujours en mots (« Prêt », « À brancher »…).
        public var status: String
        /// Ce qui est détecté (nom de la sortie, du contrôleur…).
        public var detail: String
        /// La phrase, éventuellement suivie d'un lien (`link`) puis de `hintEnd`.
        public var hint: String
        public var link: String?
        public var hintEnd: String
    }

    public let lines: [Line]

    public init(facts: HardwareFacts) {
        lines = [Self.sound(facts.output), Self.controller(facts.controller), Self.light(facts)]
    }

    public var readyCount: Int { lines.filter(\.isReady).count }
    public var isAllReady: Bool { readyCount == lines.count }

    /// « Tout est prêt », « 2 sur 3 prêts », « 1 sur 3 prêt », « Rien n’est prêt ».
    public var summary: String {
        switch readyCount {
        case lines.count: "Tout est prêt"
        case 0: "Rien n’est prêt"
        case 1: "1 sur \(lines.count) prêt"
        default: "\(readyCount) sur \(lines.count) prêts"
        }
    }

    private static let plugSpeaker = "branchez l’enceinte sur la prise casque (mini-jack)."
    private static let changeOutput = "Sortie à changer en haut de la grille."

    private static func sound(_ output: SoundOutputFact?) -> Line {
        guard let output else {
            return Line(device: .sound, isReady: false, status: "À brancher", detail: "Aucune sortie audio",
                hint: "Branchez l’enceinte sur la prise casque (mini-jack).", link: nil, hintEnd: "")
        }
        switch output.kind {
        case .builtInSpeakers:
            return Line(device: .sound, isReady: false, status: "À brancher", detail: output.name,
                hint: "Le son sort du Mac lui-même : " + plugSpeaker, link: nil, hintEnd: "")
        case .headphoneJack:
            return Line(device: .sound, isReady: true, status: "Prêt", detail: output.name,
                hint: "Le son sort par la prise casque. " + changeOutput, link: nil, hintEnd: "")
        case .other:
            return Line(device: .sound, isReady: true, status: "Prêt", detail: output.name, hint: changeOutput, link: nil, hintEnd: "")
        }
    }

    private static func controller(_ model: ControllerModel?) -> Line {
        guard let model else {
            return Line(device: .controller, isReady: false, status: "À brancher", detail: "Aucun contrôleur",
                hint: "Branchez l’APC mini mk2 ou le Launchpad Mini MK3 en USB.", link: nil, hintEnd: "")
        }
        return Line(device: .controller, isReady: true, status: "Prêt", detail: model.displayName,
            hint: "Reconnu, les pads s’allument à l’ouverture du spectacle.", link: nil, hintEnd: "")
    }

    private static func light(_ facts: HardwareFacts) -> Line {
        if facts.dmxBox {
            return Line(device: .light, isReady: true, status: "Prête", detail: "Boîtier USB-DMX",
                hint: facts.lightKey == .running
                    ? "Fermez LightKey : les deux enverraient à la barre." : "Lalabob pilote les projecteurs lui-même.",
                link: nil, hintEnd: "")
        }
        switch facts.lightKey {
        case .running:
            return Line(device: .light, isReady: true, status: "Prête", detail: "LightKey ouvert",
                hint: "Lalabob lui envoie les appuis des colonnes lumière.", link: nil, hintEnd: "")
        case .closed:
            return Line(device: .light, isReady: false, status: "À préparer", detail: "Rien de détecté",
                hint: "Branchez le boîtier USB-DMX, ou ", link: "ouvrez LightKey", hintEnd: ".")
        case .notInstalled:
            return Line(device: .light, isReady: false, status: "À préparer", detail: "Rien de détecté",
                hint: "Branchez le boîtier USB-DMX, ou installez LightKey.", link: nil, hintEnd: "")
        }
    }
}

// MARK: - État en direct

/// Comment lire le matériel. La version réelle (`live`) interroge CoreAudio, `/dev` et la liste des apps ouvertes ;
/// les tests en donnent une fausse.
@MainActor
public struct HardwareProbe {
    public var output: @MainActor () -> SoundOutputFact?
    public var dmxBox: @MainActor () -> Bool
    public var lightKey: @MainActor () -> LightKeyState

    public init(
        output: @escaping @MainActor () -> SoundOutputFact?, dmxBox: @escaping @MainActor () -> Bool,
        lightKey: @escaping @MainActor () -> LightKeyState
    ) {
        self.output = output
        self.dmxBox = dmxBox
        self.lightKey = lightKey
    }

    /// Identifiant de LightKey (relevé le 28/11/2026 dans `Lightkey.app`).
    public static let lightKeyBundleID = "de.monospc.Lightkey"

    /// L'app LightKey installée sur ce Mac, `nil` sinon.
    public static var lightKeyURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: lightKeyBundleID)
    }

    public static func live(defaults: UserDefaults = .standard) -> HardwareProbe {
        HardwareProbe(
            output: {
                AudioOutputDevices.current(preferredUID: defaults.string(forKey: ShowController.outputDefaultsKey)).map {
                    SoundOutputFact(
                        name: $0.name,
                        kind: AudioOutputKind.classify(uid: $0.uid, name: $0.name, transportType: $0.transportType, dataSource: $0.dataSource))
                }
            },
            // Sans ouvrir le port : on regarde seulement s'il existe (le banc d'essai ou le spectacle l'ouvriront).
            dmxBox: { !POSIXSerialOpener().availablePorts().isEmpty },
            lightKey: {
                if NSRunningApplication.runningApplications(withBundleIdentifier: lightKeyBundleID).isEmpty == false { return .running }
                return lightKeyURL == nil ? .notInstalled : .closed
            })
    }
}

/// L'état du matériel, relu chaque seconde tant que la fenêtre d'accueil est ouverte (rien ne tourne fenêtre fermée).
/// Une seconde suffit à l'œil, et chaque lecture coûte quelques appels système.
@MainActor
@Observable
public final class HardwareStatus {
    public private(set) var facts: HardwareFacts
    @ObservationIgnored private let probe: HardwareProbe
    @ObservationIgnored private let controller: @MainActor () -> ControllerModel?
    @ObservationIgnored private var poller: Task<Void, Never>?

    public init(probe: HardwareProbe, controller: @escaping @MainActor () -> ControllerModel?) {
        self.probe = probe
        self.controller = controller
        self.facts = HardwareFacts(output: nil, controller: nil, dmxBox: false, lightKey: .closed)
    }

    public var checklist: WelcomeChecklist { WelcomeChecklist(facts: facts) }

    public func refresh() {
        let new = HardwareFacts(output: probe.output(), controller: controller(), dmxBox: probe.dmxBox(), lightKey: probe.lightKey())
        if new != facts { facts = new }
    }

    /// Lit tout de suite, puis chaque seconde jusqu'à `stop()`.
    public func start() {
        refresh()
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
    }

    public func stop() {
        poller?.cancel()
        poller = nil
    }
}

// MARK: - Spectacles récents

/// Aperçu d'un spectacle récent : on ne lit que `show.json` (limité à 10 Mo), décodé, migré et validé comme à l'ouverture.
/// Toute erreur donne `nil` : la carte s'affiche sans aperçu, jamais d'alerte.
public enum RecentShowPreview {
    public static func load(packageURL: URL) -> ShowThumbnail? {
        let file = packageURL.appending(path: ShowPackage.showFileName)
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= ShowPackage.maximumShowFileSize,
            let data = try? Data(contentsOf: file),
            let decoded = try? ShowPackage.decodeMigrating(data)
        else { return nil }
        return ShowThumbnail(show: decoded.show)
    }

    /// « Aujourd’hui », « Hier », « 21 nov. », ou « 3 sept. 2025 » pour une autre année.
    public static func dateLabel(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Aujourd’hui" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Hier"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.dateFormat = sameYear ? "d MMM" : "d MMM y"
        return formatter.string(from: date)
    }
}
