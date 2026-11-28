/// Une trame DMX : une valeur 0–255 par canal, canaux numérotés de 1 à 512.
///
/// Seuls les premiers canaux utiles sont envoyés (`length`) : une trame courte part plus vite et plus
/// régulièrement (relevé du 27/11/2026). Écrire un canal au-delà de la longueur l'allonge.
public struct DMXFrame: Equatable, Sendable {
    public static let maximumLength = 512
    /// Minimum de la norme (DMX512-A) : en dessous, certains appareils ignorent les trames trop rapprochées.
    public static let minimumLength = 24
    /// Code de départ 0 : données de gradateurs, le seul que nous envoyons.
    public static let startCode: UInt8 = 0

    /// Valeurs des canaux 1…`length`.
    public private(set) var values: [UInt8]

    /// Trame à zéro de `length` canaux (bornée à 24…512).
    public init(length: Int = DMXFrame.minimumLength) {
        values = [UInt8](repeating: 0, count: min(max(length, Self.minimumLength), Self.maximumLength))
    }

    /// Nombre de canaux envoyés.
    public var length: Int { values.count }

    /// Valeur d'un canal (1…512). Hors bornes : lu à 0, écriture ignorée.
    public subscript(channel: Int) -> UInt8 {
        get { (1...length).contains(channel) ? values[channel - 1] : 0 }
        set {
            guard (1...Self.maximumLength).contains(channel) else { return }
            if channel > length { values += [UInt8](repeating: 0, count: channel - length) }
            values[channel - 1] = newValue
        }
    }

    /// Écrit `bytes` à partir du canal `address` (par exemple les 15 canaux d'un appareil à son adresse de départ).
    /// Ce qui dépasse le canal 512 est coupé.
    public mutating func set(_ bytes: [UInt8], from address: Int) {
        for (offset, byte) in bytes.enumerated() {
            self[address + offset] = byte
        }
    }

    /// Ce qui part sur la ligne après le break : code de départ puis canaux.
    public var packet: [UInt8] { [Self.startCode] + values }
}
