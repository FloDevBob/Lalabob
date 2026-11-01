import ControllerDrivers
import Foundation
import LalabobMIDI
import LalabobModel
import Observation

/// Banc d'essai de l'appairage lumière : montre en direct ce qui passe entre le contrôleur, Lalabob et LightKey,
/// et permet d'envoyer une note à LightKey depuis l'écran.
///
/// Rien n'est enregistré dans le spectacle. Tant que la fenêtre du banc est fermée (`isOpen == false`),
/// rien n'est noté : le jeu en scène ne paie aucun coût.
@MainActor
@Observable
public final class LightingTestBench {
    public enum Direction: Sendable {
        /// Ce que le contrôleur physique envoie à Lalabob.
        case fromController
        /// Ce que Lalabob envoie à LightKey sur « Lalabob Lumière ».
        case toLightKey
        /// Ce que LightKey renvoie sur « Lalabob Retour Lumière ».
        case fromLightKey
    }

    public struct Entry: Identifiable, Sendable {
        public let id: Int
        public let date: Date
        public let direction: Direction
        public let text: String
    }

    public static let capacity = 300

    public private(set) var entries: [Entry] = []
    /// Vrai tant que la fenêtre du banc est ouverte.
    public var isOpen = false
    /// Relayer vers LightKey les appuis du contrôleur sur les colonnes lumière (essai de l'étape 1 du plan J7).
    public var relaysControllerPresses = false
    /// Canal MIDI (1 à 16) des messages envoyés à LightKey depuis le banc et par le relais.
    public var channel = 1
    /// Contrôleur dont on utilise les notes : le contrôleur branché, sinon le dernier connu (APC mini mk2 par défaut).
    public private(set) var model: ControllerModel = .apcMiniMK2
    public private(set) var isControllerConnected = false
    /// Cases tenues sur le contrôleur physique.
    public private(set) var controllerPressed: Set<GridPosition> = []
    /// Cases tenues avec la souris.
    public private(set) var screenPressed: Set<GridPosition> = []
    /// Dernière vélocité reçue de LightKey pour chaque note (0 = éteint).
    public private(set) var lightKeyLevels: [UInt8: UInt8] = [:]
    public private(set) var feedbackCount = 0

    @ObservationIgnored private var nextID = 0
    /// Envoi vers LightKey, fourni par la session.
    @ObservationIgnored var send: (([MIDIEvent]) -> Void)?

    public init() {}

    /// Nom du contrôleur dont on utilise les notes.
    public var controllerName: String { model.displayName }

    /// Note que le contrôleur envoie pour cette case.
    public func note(at position: GridPosition) -> Int { Int(model.driver.note(for: position)) }

    var channelByte: UInt8 { UInt8(min(max(channel, 1), 16) - 1) }

    // MARK: - Écran

    public func press(_ position: GridPosition) {
        guard position.isValid, screenPressed.insert(position).inserted else { return }
        send?([.noteOn(channel: channelByte, note: model.driver.note(for: position), velocity: 127)])
    }

    public func release(_ position: GridPosition) {
        guard screenPressed.remove(position) != nil else { return }
        send?([.noteOff(channel: channelByte, note: model.driver.note(for: position), velocity: 0)])
    }

    public func clear() {
        entries = []
        lightKeyLevels = [:]
        feedbackCount = 0
    }

    /// Le journal en texte, pour le coller dans une conversation ou un rapport.
    public var transcript: String {
        entries.map { entry in
            let time = entry.date.formatted(.dateTime.hour().minute().second())
            return "\(time) \(Self.label(entry.direction)) \(entry.text)"
        }.joined(separator: "\n")
    }

    public static func label(_ direction: Direction) -> String {
        switch direction {
        case .fromController: "Contrôleur →"
        case .toLightKey: "→ LightKey"
        case .fromLightKey: "LightKey →"
        }
    }

    // MARK: - Alimenté par la session

    func record(_ direction: Direction, _ events: [MIDIEvent]) {
        guard isOpen else { return }
        for event in events {
            entries.append(Entry(id: nextID, date: Date(), direction: direction, text: event.summary))
            nextID += 1
        }
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    func recordFeedback(_ events: [MIDIEvent]) {
        guard isOpen else { return }
        record(.fromLightKey, events)
        feedbackCount += events.count
        for event in events {
            switch event {
            case .noteOn(_, let note, let velocity): lightKeyLevels[note] = velocity
            case .noteOff(_, let note, _): lightKeyLevels[note] = 0
            default: break
            }
        }
    }

    func setController(_ model: ControllerModel?) {
        if let model { self.model = model }
        isControllerConnected = model != nil
        if model == nil { controllerPressed = [] }
    }

    func setControllerPad(_ position: GridPosition, pressed: Bool) {
        guard isOpen else { return }
        if pressed { controllerPressed.insert(position) } else { controllerPressed.remove(position) }
    }
}
