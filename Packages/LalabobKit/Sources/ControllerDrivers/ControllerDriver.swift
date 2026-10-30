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

    /// Pilote correspondant.
    public var driver: any ControllerDriver {
        switch self {
        case .launchpadX, .launchpadMiniMK3, .launchpadProMK3:
            return LaunchpadDriver(model: self)
        case .apcMiniMK2:
            return APCMiniMK2Driver()
        }
    }
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
}
