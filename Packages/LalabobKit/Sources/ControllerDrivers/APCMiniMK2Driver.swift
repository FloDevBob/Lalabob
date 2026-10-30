import LalabobMIDI
import LalabobModel

/// Pilote de l'Akai APC mini mk2.
///
/// Voir docs/hardware/apc-mini-mk2.md.
/// - Grille : notes 0 (en bas à gauche) à 63 (en haut à droite), note = rangée depuis le bas × 8 + colonne.
/// - LED : Note On, vélocité = couleur de la palette, canal = luminosité
///   (canal 0 = 10 % … canal 6 = 100 % ; au-delà : pulsation puis clignotement).
/// - Faders : CC 48 à 55 pour les 8 colonnes. Le 9e fader (CC 56) est volontairement ignoré :
///   il est mappé dans un autre logiciel (volume d'Apple Music), qui lit l'APC en parallèle.
public struct APCMiniMK2Driver: ControllerDriver {
    public let model = ControllerModel.apcMiniMK2

    public init() {}

    static let firstFaderCC: UInt8 = 48
    static let masterFaderCC: UInt8 = 56

    public var connectionMessages: [MIDIEvent] {
        ledMessages(Dictionary(uniqueKeysWithValues: GridPosition.all.map { ($0, LEDState.off) }))
    }

    public var disconnectionMessages: [MIDIEvent] { connectionMessages }

    public func note(for position: GridPosition) -> UInt8 {
        precondition(position.isValid)
        let rowFromBottom = PadGrid.size - 1 - position.row
        return UInt8(rowFromBottom * PadGrid.size + position.column)
    }

    public func position(forNote note: UInt8) -> GridPosition? {
        guard note < UInt8(PadGrid.size * PadGrid.size) else { return nil }
        let rowFromBottom = Int(note) / PadGrid.size
        return GridPosition(column: Int(note) % PadGrid.size, row: PadGrid.size - 1 - rowFromBottom)
    }

    public func interpret(_ event: MIDIEvent) -> ControllerInput? {
        switch event {
        case let .noteOn(_, note, velocity):
            return position(forNote: note).map { .padPressed($0, velocity: velocity) }
        case let .noteOff(_, note, _):
            return position(forNote: note).map { .padReleased($0) }
        case let .controlChange(_, controller, value):
            guard controller >= Self.firstFaderCC, controller < Self.masterFaderCC else { return nil }
            return .columnFader(column: Int(controller - Self.firstFaderCC), value: Double(value) / 127)
        case .systemExclusive:
            return nil
        }
    }

    /// Canal MIDI selon l'intensité voulue.
    static func brightnessChannel(_ intensity: LEDIntensity) -> UInt8 {
        switch intensity {
        case .full: 6       // 100 %
        case .pastel: 4     // 75 %
        case .half: 2       // 50 %
        case .quarter: 1    // 25 %
        }
    }

    /// Premier canal de pulsation (à confirmer sur le matériel).
    static let pulseChannel: UInt8 = 9

    public func ledMessages(_ updates: [GridPosition: LEDState]) -> [MIDIEvent] {
        updates
            .filter { $0.key.isValid }
            .sorted { note(for: $0.key) < note(for: $1.key) }
            .map { entry -> MIDIEvent in
                let index = note(for: entry.key)
                return switch entry.value {
                case .off:
                    .noteOn(channel: 0, note: index, velocity: 0)
                case let .lit(tint, intensity):
                    .noteOn(channel: Self.brightnessChannel(intensity), note: index, velocity: tint.spec.paletteVelocity)
                case let .pulsing(tint):
                    .noteOn(channel: Self.pulseChannel, note: index, velocity: tint.spec.paletteVelocity)
                }
            }
    }
}
