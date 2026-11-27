import Foundation

/// Un boîtier USB-DMX vu par macOS comme un port série (`/dev/cu.…`).
public struct DMXPortInfo: Hashable, Sendable, Identifiable {
    /// Chemin du port, par exemple `/dev/cu.usbserial-AU0483EN`.
    public let path: String

    public init(path: String) { self.path = path }

    public var id: String { path }

    /// Numéro de série lu dans le nom du port (« AU0483EN » pour le boîtier FTDI de la troupe), vide si inconnu.
    /// Il sert à reconnaître le boîtier choisi sur ce Mac, même s'il change de prise USB.
    public var serialNumber: String {
        let name = (path as NSString).lastPathComponent
        for prefix in DMXPortDiscovery.serialPrefixes where name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return ""
    }

    /// Nom affiché.
    public var name: String {
        serialNumber.isEmpty ? "Boîtier USB-DMX" : "Boîtier USB-DMX \(serialNumber)"
    }
}

public enum DMXError: Error, Equatable, Sendable {
    case openFailed(code: Int32, message: String)
    case configurationFailed(code: Int32, message: String)
    case breakFailed(code: Int32, message: String)
    case writeFailed(code: Int32, message: String)

    /// Texte du système, pour l'état affiché (« Resource busy », « Device not configured »…).
    public var message: String {
        switch self {
        case .openFailed(_, let m), .configurationFailed(_, let m), .breakFailed(_, let m), .writeFailed(_, let m): m
        }
    }
}

/// Une ligne série ouverte. Utilisée par un seul fil à la fois (celui de la sortie DMX).
public protocol SerialLine: Sendable {
    /// Début (`true`) ou fin (`false`) du « break » : la ligne est tenue à 0.
    func setBreak(_ on: Bool) throws
    func write(_ bytes: [UInt8]) throws
    /// Attend que tous les octets écrits soient partis.
    func drain() throws
    func close()
}

/// Accès aux ports série du Mac. Version réelle : `POSIXSerialOpener` ; les tests utilisent un faux.
public protocol SerialLineOpener: Sendable {
    func availablePorts() -> [DMXPortInfo]
    /// Ouvre le port, réglé pour le DMX (250 kbit/s, 8 bits, 2 bits d'arrêt, sans parité).
    func open(_ port: DMXPortInfo) throws -> any SerialLine
}

/// Recherche des boîtiers parmi les ports série.
public enum DMXPortDiscovery {
    /// Préfixes des ports série des puces USB courantes : FTDI (Open DMX, Enttec), CH340, CP210x.
    static let serialPrefixes = ["cu.usbserial-", "cu.usbserial", "cu.wchusbserial", "cu.SLAB_USBtoUART"]

    /// Boîtiers possibles parmi les noms de `/dev`, triés. Seuls les ports « cu » (appel sortant) sont gardés.
    public static func candidates(deviceNames: [String]) -> [DMXPortInfo] {
        deviceNames
            .filter { name in serialPrefixes.contains { name.hasPrefix($0) } }
            .sorted()
            .map { DMXPortInfo(path: "/dev/" + $0) }
    }

    /// Le boîtier choisi sur ce Mac s'il est branché, sinon le premier branché.
    public static func choose(from ports: [DMXPortInfo], preferredSerial: String?) -> DMXPortInfo? {
        if let preferredSerial, let port = ports.first(where: { $0.serialNumber == preferredSerial }) {
            return port
        }
        return ports.first
    }
}
