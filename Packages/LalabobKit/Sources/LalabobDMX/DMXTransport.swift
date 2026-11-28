import Synchronization

/// État de la sortie DMX, pour l'en-tête (« Projecteurs ») et le banc d'essai.
public enum DMXStatus: Equatable, Sendable {
    /// Sortie pas encore démarrée, ou arrêtée.
    case stopped
    /// Aucun boîtier USB-DMX branché ; on regarde de nouveau chaque seconde.
    case noDevice
    /// Le boîtier reçoit la trame en continu.
    case connected(DMXPortInfo)
    /// Boîtier vu mais en erreur (débranché en jouant, pris par une autre app…) ; nouvel essai chaque seconde.
    case failed(DMXPortInfo, String)

    public var isConnected: Bool {
        if case .connected = self { true } else { false }
    }
}

/// Sortie DMX vue par le moteur. Version réelle : `DMXOutput` (son propre fil) ; tests : `SilentDMX`.
///
/// Le moteur ne fait que poser la trame voulue (`setFrame`) : l'envoi continu, le rebranchement et la cadence
/// sont l'affaire de la sortie. Aucune méthode ne bloque l'appelant.
public protocol DMXTransport: AnyObject, Sendable {
    var status: DMXStatus { get }
    /// Chaque changement d'état (un seul lecteur).
    var statusUpdates: AsyncStream<DMXStatus> { get }

    /// Démarre l'envoi continu (sans effet si déjà démarré).
    func start()
    /// Trame fixe envoyée à partir du prochain rafraîchissement (remplace une source).
    func setFrame(_ frame: DMXFrame)
    /// Trame recalculée à chaque rafraîchissement (fondus de la console) ; `nil` = garder la dernière trame calculée.
    func setSource(_ source: (any DMXFrameSource)?)
    /// Boîtier choisi sur ce Mac (numéro de série), `nil` = le premier branché.
    func selectPort(serialNumber: String?)
    func availablePorts() -> [DMXPortInfo]
    /// Envoie `finalFrame` (par exemple le noir) quelques fois, puis ferme le port. Plus rien ne part ensuite.
    func shutdown(finalFrame: DMXFrame?) async
}

/// Sortie muette : garde la dernière trame, ne touche à aucun port. Pour les tests et sans boîtier.
public final class SilentDMX: DMXTransport {
    private struct State {
        var status: DMXStatus = .stopped
        var frame = DMXFrame()
        var source: (any DMXFrameSource)?
    }
    private let state = Mutex(State())
    public let statusUpdates: AsyncStream<DMXStatus>
    private let continuation: AsyncStream<DMXStatus>.Continuation

    public init() {
        (statusUpdates, continuation) = AsyncStream.makeStream(of: DMXStatus.self, bufferingPolicy: .bufferingNewest(8))
    }

    public var status: DMXStatus { state.withLock { $0.status } }
    /// La trame qui partirait maintenant.
    public var lastFrame: DMXFrame { frame(at: DMXClock.now()) }

    /// La trame qui partirait à cet instant (secondes de `DMXClock`).
    public func frame(at time: Double) -> DMXFrame {
        let (frame, source) = state.withLock { ($0.frame, $0.source) }
        return source?.frame(at: time) ?? frame
    }

    public func start() { update(.noDevice) }
    public func setFrame(_ frame: DMXFrame) {
        state.withLock {
            $0.frame = frame
            $0.source = nil
        }
    }
    public func setSource(_ source: (any DMXFrameSource)?) {
        state.withLock { s in
            if source == nil, let old = s.source { s.frame = old.frame(at: DMXClock.now()) }
            s.source = source
        }
    }
    public func selectPort(serialNumber: String?) {}
    public func availablePorts() -> [DMXPortInfo] { [] }

    public func shutdown(finalFrame: DMXFrame?) async {
        if let finalFrame { setFrame(finalFrame) }
        update(.stopped)
    }

    private func update(_ status: DMXStatus) {
        state.withLock { $0.status = status }
        continuation.yield(status)
    }
}
