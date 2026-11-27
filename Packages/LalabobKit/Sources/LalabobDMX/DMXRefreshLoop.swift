/// Cœur du fil DMX, un pas par rafraîchissement : ouvre le boîtier s'il le faut, envoie la trame, gère le débranchement.
///
/// Valeur appartenant au seul fil de la sortie (`DMXOutput`) ; le temps est passé en paramètre pour que les tests
/// rejouent un branchement, un débranchement et un rebranchement sans attendre.
public struct DMXRefreshLoop {
    /// Délai entre deux essais d'ouverture quand il n'y a pas de boîtier ou qu'il est en erreur.
    public static let retryInterval: Duration = .seconds(1)

    let opener: any SerialLineOpener
    let writer: OpenDMXWriter
    private var line: (any SerialLine)?
    private var port: DMXPortInfo?
    private var nextAttempt: ContinuousClock.Instant?
    public private(set) var status: DMXStatus = .stopped

    public init(opener: any SerialLineOpener, writer: OpenDMXWriter) {
        self.opener = opener
        self.writer = writer
    }

    /// Un rafraîchissement. `reselect` : le boîtier choisi a changé, on ferme l'actuel pour rouvrir le bon.
    /// Renvoie vrai si l'état a changé.
    @discardableResult
    public mutating func step(
        frame: DMXFrame, preferredSerial: String?, reselect: Bool, now: ContinuousClock.Instant
    ) -> Bool {
        let before = status
        if reselect {
            closeLine()
            nextAttempt = nil
        }
        if line == nil { open(preferredSerial: preferredSerial, now: now) }
        if let line, let port {
            do {
                try writer.send(frame, on: line)
                status = .connected(port)
            } catch {
                // Débranché ou en erreur : on lâche la ligne. La barre garde sa dernière couleur (relevé du 27/11/2026) ;
                // la trame en cours repart dès la réouverture.
                closeLine()
                status = .failed(port, (error as? DMXError)?.message ?? "\(error)")
                nextAttempt = now + Self.retryInterval
            }
        }
        return status != before
    }

    /// Ferme le port ; la boucle repart de zéro au prochain pas.
    public mutating func close() {
        closeLine()
        nextAttempt = nil
        status = .stopped
    }

    private mutating func open(preferredSerial: String?, now: ContinuousClock.Instant) {
        if let nextAttempt, now < nextAttempt { return }
        nextAttempt = now + Self.retryInterval
        guard let candidate = DMXPortDiscovery.choose(from: opener.availablePorts(), preferredSerial: preferredSerial)
        else {
            status = .noDevice
            return
        }
        do {
            line = try opener.open(candidate)
            port = candidate
        } catch {
            status = .failed(candidate, (error as? DMXError)?.message ?? "\(error)")
        }
    }

    private mutating func closeLine() {
        line?.close()
        line = nil
    }
}
