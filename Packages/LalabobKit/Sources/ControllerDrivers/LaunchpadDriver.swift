import LalabobMIDI
import LalabobModel

/// Pilote des Launchpad X, Mini MK3 et Pro MK3 en mode Programmeur.
///
/// Référence : « Launchpad X Programmer's reference manual » (Novation), voir docs/hardware/launchpad-mk3.md.
/// - En-tête SysEx : F0 00 20 29 02 <modèle>
/// - Mode Programmeur : <en-tête> 0E 01 F7
/// - LED : <en-tête> 03 { type, index, données… } F7, type 3 = RVB (0–127 par canal)
/// - Grille : note = (rangée depuis le bas + 1) × 10 + (colonne + 1), soit 11 en bas à gauche, 88 en haut à droite.
public struct LaunchpadDriver: ControllerDriver {
    public let model: ControllerModel

    public init(model: ControllerModel) {
        precondition(model != .apcMiniMK2, "Utilisez APCMiniMK2Driver")
        self.model = model
    }

    /// Octet modèle de l'en-tête SysEx.
    /// Launchpad X = 0C (manuel vérifié). Mini MK3 = 0D et Pro MK3 = 0E : à confirmer sur le matériel.
    var modelByte: UInt8 {
        switch model {
        case .launchpadX: 0x0C
        case .launchpadMiniMK3: 0x0D
        case .launchpadProMK3: 0x0E
        case .apcMiniMK2: preconditionFailure()
        }
    }

    var sysExHeader: [UInt8] { [0xF0, 0x00, 0x20, 0x29, 0x02, modelByte] }

    public var connectionMessages: [MIDIEvent] {
        [.systemExclusive(sysExHeader + [0x0E, 0x01, 0xF7])]
            + ledMessages(Dictionary(uniqueKeysWithValues: GridPosition.all.map { ($0, LEDState.off) }))
    }

    public var disconnectionMessages: [MIDIEvent] {
        [.systemExclusive(sysExHeader + [0x0E, 0x00, 0xF7])]
    }

    public func note(for position: GridPosition) -> UInt8 {
        precondition(position.isValid)
        let rowFromBottom = PadGrid.size - 1 - position.row
        return UInt8((rowFromBottom + 1) * 10 + position.column + 1)
    }

    public func position(forNote note: UInt8) -> GridPosition? {
        let tens = Int(note) / 10
        let units = Int(note) % 10
        guard (1...PadGrid.size).contains(tens), (1...PadGrid.size).contains(units) else { return nil }
        return GridPosition(column: units - 1, row: PadGrid.size - tens)
    }

    public func interpret(_ event: MIDIEvent) -> ControllerInput? {
        switch event {
        case let .noteOn(_, note, velocity):
            position(forNote: note).map { .padPressed($0, velocity: velocity) }
        case let .noteOff(_, note, _):
            position(forNote: note).map { .padReleased($0) }
        default:
            nil
        }
    }

    /// Nombre maximal de LED par message SysEx (manuel : 81).
    static let maximumLEDsPerMessage = 81

    public func ledMessages(_ updates: [GridPosition: LEDState]) -> [MIDIEvent] {
        let specs: [[UInt8]] = updates
            .filter { $0.key.isValid }
            .sorted { note(for: $0.key) < note(for: $1.key) }
            .map { entry -> [UInt8] in
                let index = note(for: entry.key)
                switch entry.value {
                case .off:
                    return [0x00, index, 0x00]
                case let .lit(tint, intensity):
                    let color = intensity.apply(to: tint.spec.vivid)
                    return [0x03, index] + Self.sevenBit(color)
                case let .pulsing(tint):
                    return [0x02, index, tint.spec.paletteVelocity]
                }
            }
        return stride(from: 0, to: specs.count, by: Self.maximumLEDsPerMessage).map { start -> MIDIEvent in
            let chunk = specs[start..<min(start + Self.maximumLEDsPerMessage, specs.count)]
            return .systemExclusive(sysExHeader + [0x03] + chunk.flatMap { $0 } + [0xF7])
        }
    }

    /// Ramène une couleur 8 bits à l'échelle 0–127 du Launchpad.
    static func sevenBit(_ color: RGB) -> [UInt8] {
        [color.red >> 1, color.green >> 1, color.blue >> 1]
    }
}
