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
    /// Étalonnage des couleurs, utilisé seulement en mode RVB libre (la palette d'Akai n'est pas étalonnable).
    public let calibration: LEDCalibration
    /// Couleurs en **SysEx RVB** (une couleur libre par pad) au lieu de la palette par vélocité. À valider sur le matériel.
    public let usesRGB: Bool

    public init(calibration: LEDCalibration = .neutral, usesRGB: Bool = false) {
        self.calibration = calibration
        self.usesRGB = usesRGB
    }

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

    /// CC du fader de la colonne (48 + colonne), valeur 0…127 ; jamais le 9e fader.
    public func faderEvent(column: Int, value: Double) -> MIDIEvent? {
        guard (0..<Int(Self.masterFaderCC - Self.firstFaderCC)).contains(column) else { return nil }
        let clamped = value.isFinite ? min(max(value, 0), 1) : 0
        return .controlChange(channel: 0, controller: Self.firstFaderCC + UInt8(column), value: UInt8((clamped * 127).rounded()))
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

    /// SysEx « pad RVB » : `F0 47 7F 4F 24 <longueur sur 2 octets> <pad début> <pad fin> <R> <G> <B> F7`, chaque canal
    /// de 0 à 255 étant coupé en deux octets de 7 bits (poids fort : 0 ou 1, puis les 7 bits de poids faible) ⚠︎ à valider
    /// sur le matériel (protocole Akai, APC mini mk2 Communication Protocol).
    static func rgbSysEx(pad: UInt8, color: RGB) -> MIDIEvent {
        func split(_ value: UInt8) -> [UInt8] { [value >> 7, value & 0x7F] }
        return .systemExclusive(
            [0xF0, 0x47, 0x7F, 0x4F, 0x24, 0x00, 0x08, pad, pad] + split(color.red) + split(color.green) + split(color.blue)
                + [0xF7])
    }

    public func ledMessages(_ updates: [GridPosition: LEDState]) -> [MIDIEvent] {
        updates
            .filter { $0.key.isValid }
            .sorted { note(for: $0.key) < note(for: $1.key) }
            .map { entry -> MIDIEvent in
                let index = note(for: entry.key)
                switch entry.value {
                case .off:
                    return usesRGB ? Self.rgbSysEx(pad: index, color: RGB(red: 0, green: 0, blue: 0)) : .noteOn(channel: 0, note: index, velocity: 0)
                case let .lit(tint, intensity):
                    guard usesRGB else {
                        return .noteOn(channel: Self.brightnessChannel(intensity), note: index, velocity: tint.spec.paletteVelocity)
                    }
                    // Étalonnage d'abord (la couleur de la LED), intensité ensuite (la commande de la LED).
                    return Self.rgbSysEx(pad: index, color: intensity.apply(to: calibration.apply(to: tint.spec.vivid)))
                case let .pulsing(tint):
                    // La pulsation est un comportement de la palette (canal) : elle reste en palette dans les deux modes.
                    return .noteOn(channel: Self.pulseChannel, note: index, velocity: tint.spec.paletteVelocity)
                }
            }
    }
}
