import LalabobMIDI
import LalabobModel

/// Les contrôleurs pris en charge.
public enum ControllerModel: String, CaseIterable, Sendable {
    case launchpadX, launchpadMiniMK3, launchpadProMK3, apcMiniMK2

    public var displayName: String {
        switch self {
        case .launchpadX: "Launchpad X"
        case .launchpadMiniMK3: "Launchpad Mini MK3"
        case .launchpadProMK3: "Launchpad Pro MK3"
        case .apcMiniMK2: "APC mini mk2"
        }
    }

    /// Pilote correspondant, sans étalonnage (notes, entrées, messages : tout ce qui n'est pas de la couleur).
    public var driver: any ControllerDriver { driver(settings: .neutral) }

    /// Pilote avec l'étalonnage des couleurs (Launchpad ; l'APC reste sur sa palette).
    public func driver(calibration: LEDCalibration) -> any ControllerDriver {
        driver(settings: LEDSettings(calibration: calibration))
    }

    /// Pilote avec les réglages de couleur : étalonnage RVB du Launchpad, ou palette / RVB libre de l'APC mini mk2.
    public func driver(settings: LEDSettings) -> any ControllerDriver {
        switch self {
        case .launchpadX, .launchpadMiniMK3, .launchpadProMK3:
            return LaunchpadDriver(model: self, calibration: settings.calibration)
        case .apcMiniMK2:
            return APCMiniMK2Driver(calibration: settings.calibration, usesRGB: settings.usesRGB)
        }
    }

    /// Les LED de ce contrôleur sont toujours en RVB : l'étalonnage a toujours un effet. L'APC mini mk2 n'y est qu'en
    /// mode « RVB libre ».
    public var hasRGBLEDs: Bool { self != .apcMiniMK2 }

    /// Les réglages de couleur sont communs aux modèles d'une même famille (clé de mémorisation).
    public var ledFamily: String { self == .apcMiniMK2 ? "apc" : "launchpad" }
}

/// État visuel demandé pour la LED d'une case.
public enum LEDState: Equatable, Sendable {
    case off
    case lit(Tint, LEDIntensity)
    /// Clignotement doux : son en lecture, cue active.
    case pulsing(Tint)
}

/// Ce que l'app comprend d'un message reçu d'un contrôleur.
public enum ControllerInput: Equatable, Sendable {
    case padPressed(GridPosition, velocity: UInt8)
    case padReleased(GridPosition)
    /// Fader de colonne déplacé, valeur de 0 à 1.
    case columnFader(column: Int, value: Double)
    /// Bouton « stop » sous une colonne enfoncé (APC mini mk2).
    case columnStop(column: Int)
}

/// Un pilote traduit entre le langage d'un contrôleur et la grille 8×8 de Lalabob.
///
/// Règle d'or : un pilote est une fonction pure (octets ⇄ valeurs), sans état ni E/S.
/// L'envoi et la réception passent par LalabobMIDI. Tout pilote est donc testable sans matériel.
public protocol ControllerDriver: Sendable {
    var model: ControllerModel { get }

    /// Messages à envoyer à la connexion (passage en mode Programmeur, extinction…).
    var connectionMessages: [MIDIEvent] { get }

    /// Messages à envoyer à la déconnexion propre (retour au mode d'origine).
    var disconnectionMessages: [MIDIEvent] { get }

    /// Note MIDI d'une case.
    func note(for position: GridPosition) -> UInt8

    /// Case correspondant à une note, ou `nil` si la note est hors grille.
    func position(forNote note: UInt8) -> GridPosition?

    /// Traduit un message reçu en action Lalabob, ou `nil` s'il ne concerne pas Lalabob.
    func interpret(_ event: MIDIEvent) -> ControllerInput?

    /// Messages pour mettre à jour un ensemble de LED.
    func ledMessages(_ updates: [GridPosition: LEDState]) -> [MIDIEvent]

    /// Message que le contrôleur enverrait si son fader de cette colonne passait à `value` (0…1) ; `nil` s'il
    /// n'a pas de fader pour cette colonne. Sert à répéter vers LightKey un fader déplacé à l'écran.
    func faderEvent(column: Int, value: Double) -> MIDIEvent?

    /// Les boutons « stop » sous les colonnes (APC mini mk2) : `litColumns` allumés, les autres éteints. Vide sinon.
    /// Une exigence du protocole (et non une simple extension) pour que chaque pilote fournisse la sienne.
    func stopButtonMessages(litColumns: Set<Int>) -> [MIDIEvent]
}

extension ControllerDriver {
    public func faderEvent(column: Int, value: Double) -> MIDIEvent? { nil }

    /// Aucun bouton « stop » par défaut (Launchpad).
    public func stopButtonMessages(litColumns: Set<Int>) -> [MIDIEvent] { [] }

    /// Ce qu'on envoie en quittant l'app : toutes les LED éteintes, puis le retour au mode d'origine du contrôleur.
    public var shutdownMessages: [MIDIEvent] {
        ledMessages(Dictionary(uniqueKeysWithValues: GridPosition.all.map { ($0, LEDState.off) }))
            + stopButtonMessages(litColumns: []) + disconnectionMessages
    }
}

extension ControllerDriver {
    /// Ce que LightKey dit d'une cue : Note On (vélocité > 0) = allumée, Note Off = éteinte, sur la note de la case.
    /// Le canal est ignoré (LightKey répond sur celui qu'il a appris). `nil` si le message ne concerne aucune case.
    public func lightFeedback(for event: MIDIEvent) -> (position: GridPosition, state: LightState)? {
        switch event {
        case let .noteOn(_, note, velocity):
            return position(forNote: note).map { ($0, velocity > 0 ? .on : .off) }
        case let .noteOff(_, note, _):
            return position(forNote: note).map { ($0, .off) }
        case .controlChange, .systemExclusive:
            return nil
        }
    }
}
