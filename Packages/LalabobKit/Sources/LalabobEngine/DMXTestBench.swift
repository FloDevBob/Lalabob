import Foundation
import LalabobDMX
import Observation

/// Banc d'essai DMX (J14, étape 1) : un curseur par canal de la barre (15 canaux), pour vérifier le tableau du manuel,
/// l'adresse et le boîtier, sans toucher au spectacle.
///
/// La sortie ne tourne que fenêtre ouverte. Fermer arrête le signal sans envoyer de noir : la barre garde sa dernière
/// couleur (relevé du 27/11/2026) ; le bouton Noir est là pour éteindre.
@MainActor
@Observable
public final class DMXTestBench {
    /// Canaux de la Chauvet DJ 4BAR LT BT en mode 15 canaux (`docs/hardware/chauvet-4bar-ltbt.md`).
    public static let channelNames: [String] =
        ["Programme (0 = pilotage DMX)", "Gradateur général", "Strobo"]
        + (1...4).flatMap { head in ["rouge", "vert", "bleu"].map { "Projecteur \(head) · \($0)" } }
    /// 498 au plus, pour que les 15 canaux tiennent dans les 512.
    public static let addressRange = 1...(DMXFrame.maximumLength - 14)
    private static let addressKey = "dmxBenchAddress"
    /// Boîtier choisi sur ce Mac (comme la sortie audio) ; repris plus tard par la console lumière.
    public static let portKey = "dmxPortSerial"

    /// Adresse de départ réglée sur la barre (MENU → 15Ch → d …).
    public var address: Int {
        didSet {
            let clamped = min(max(address, Self.addressRange.lowerBound), Self.addressRange.upperBound)
            if clamped != address { address = clamped; return }
            defaults.set(address, forKey: Self.addressKey)
            sendFrame()
        }
    }
    /// Valeurs des 15 canaux, depuis l'adresse.
    public private(set) var values: [UInt8] = [0, 255, 0] + [UInt8](repeating: 0, count: 12)
    public private(set) var status: DMXStatus = .stopped
    public private(set) var ports: [DMXPortInfo] = []
    /// Numéro de série du boîtier choisi, `nil` = le premier branché.
    public var selectedSerial: String? {
        didSet {
            defaults.set(selectedSerial, forKey: Self.portKey)
            transport?.selectPort(serialNumber: selectedSerial)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeTransport: () -> any DMXTransport
    @ObservationIgnored private var transport: (any DMXTransport)?
    @ObservationIgnored private var statusTask: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard, makeTransport: @escaping () -> any DMXTransport = { DMXOutput() }
    ) {
        self.defaults = defaults
        self.makeTransport = makeTransport
        let saved = defaults.integer(forKey: Self.addressKey)
        address = Self.addressRange.contains(saved) ? saved : 1
        selectedSerial = defaults.string(forKey: Self.portKey)
    }

    public var isRunning: Bool { transport != nil }

    /// Trame envoyée : les 15 canaux posés à l'adresse.
    public var frame: DMXFrame {
        var frame = DMXFrame()
        frame.set(values, from: address)
        return frame
    }

    /// Démarre l'envoi (fenêtre ouverte). Sans effet si déjà démarré.
    public func open() {
        guard transport == nil else { return }
        let transport = makeTransport()
        self.transport = transport
        transport.selectPort(serialNumber: selectedSerial)
        transport.setFrame(frame)
        transport.start()
        status = transport.status
        let updates = transport.statusUpdates
        statusTask = Task { [weak self] in
            for await status in updates {
                guard let self else { return }
                self.status = status
                self.refreshPorts()
            }
        }
        refreshPorts()
    }

    /// Arrête l'envoi (fenêtre fermée), sans noir.
    public func close() async {
        guard let transport else { return }
        self.transport = nil
        statusTask?.cancel()
        statusTask = nil
        await transport.shutdown(finalFrame: nil)
        status = .stopped
    }

    public func refreshPorts() {
        ports = transport?.availablePorts() ?? []
    }

    /// Règle un canal (0…14, depuis l'adresse).
    public func setValue(_ value: UInt8, at offset: Int) {
        guard values.indices.contains(offset) else { return }
        values[offset] = value
        sendFrame()
    }

    /// Les 4 projecteurs en blanc, gradateur à 100 %, sans strobo.
    public func white() {
        values = [0, 255, 0] + [UInt8](repeating: 255, count: 12)
        sendFrame()
    }

    /// Tout à zéro.
    public func black() {
        values = [UInt8](repeating: 0, count: 15)
        sendFrame()
    }

    private func sendFrame() { transport?.setFrame(frame) }
}

// L'app ne dépend que de LalabobEngine : elle y trouve les types DMX dont l'interface a besoin.
public typealias DMXStatus = LalabobDMX.DMXStatus
public typealias DMXPortInfo = LalabobDMX.DMXPortInfo
