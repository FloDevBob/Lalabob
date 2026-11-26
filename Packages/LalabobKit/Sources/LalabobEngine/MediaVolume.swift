import Foundation

/// Ce que Lalabob sait de l'application dont il règle le volume (Apple Music).
public enum MediaVolumeStatus: Equatable, Sendable {
    /// L'application tourne : on peut régler son volume.
    case running
    /// L'application n'est pas lancée : rien n'est envoyé (Lalabob ne la lance jamais).
    case notRunning
    /// macOS a refusé à Lalabob le droit de la piloter (Réglages Système › Confidentialité › Automatisation).
    case notAuthorized
    /// Music a répondu par une erreur (texte pour le diagnostic).
    case failed(String)
}

/// Erreurs que `setVolume` peut signaler précisément.
public enum MediaVolumeError: Error, Equatable, Sendable {
    case notAuthorized
    case failed(String)
}

/// Règle le volume d'une application de musique. Une seule implémentation réelle (`AppleMusicVolume`) ; les tests en fournissent une fausse.
public protocol MediaVolumeControlling: Sendable {
    func status() async -> MediaVolumeStatus
    /// Règle le volume (0 à 100). Ne doit jamais lancer l'application.
    func setVolume(percent: Int) async throws
    /// Lit le volume actuel (0 à 100) sans rien changer ; `nil` si l'application n'est pas lancée. Sert au diagnostic.
    func currentVolume() async throws -> Int?
}

/// Transforme les mouvements du 9e fader en réglages de volume, comme le faisait le script Python : `int(valeur / 127 × 100)`,
/// un écart d'au moins 2 % avec le dernier envoi, et **au plus un envoi toutes les 66 ms** (la dernière valeur gagne et part toujours).
/// Les extrêmes (0 % et 100 %) partent même à moins de 2 % du dernier envoi : le fader au bout doit donner le silence ou le plein volume.
public actor MediaVolumeRelay {
    public typealias Update = @Sendable (MediaVolumeStatus, Int?) -> Void

    private let target: any MediaVolumeControlling
    private let minimumInterval: Duration
    private let threshold: Int
    private let onUpdate: Update
    private let clock = ContinuousClock()
    private var isEnabled: Bool
    private var lastSent: Int?
    private var lastSendTime: ContinuousClock.Instant?
    private var pending: Int?
    private var flushTask: Task<Void, Never>?

    public init(
        target: any MediaVolumeControlling, isEnabled: Bool = true, minimumInterval: Duration = .milliseconds(66), threshold: Int = 2,
        onUpdate: @escaping Update = { _, _ in }
    ) {
        self.target = target
        self.isEnabled = isEnabled
        self.minimumInterval = minimumInterval
        self.threshold = threshold
        self.onUpdate = onUpdate
    }

    /// Conversion du script : 0…1 → 0…100 (partie entière, comme `int(valeur / 127 × 100)`).
    public static func percent(forFader value: Double) -> Int {
        let clamped = value.isFinite ? min(max(value, 0), 1) : 0
        return Int((clamped * 100).rounded(.down))
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            pending = nil
            flushTask?.cancel()
            flushTask = nil
        }
    }

    /// Le fader a bougé (valeur de 0 à 1).
    public func faderMoved(to value: Double) {
        guard isEnabled else { return }
        let percent = Self.percent(forFader: value)
        guard isWorthSending(percent) else { return }
        let now = clock.now
        if let last = lastSendTime, now - last < minimumInterval {
            pending = percent  // la dernière valeur gagne ; elle partira à la fin de l'intervalle
            if flushTask == nil {
                let wait = minimumInterval - (now - last)
                flushTask = Task { [weak self] in
                    try? await Task.sleep(for: wait)
                    await self?.flush()
                }
            }
        } else {
            pending = nil
            Task { await send(percent) }
        }
    }

    private func isWorthSending(_ percent: Int) -> Bool {
        guard let lastSent else { return true }
        if percent == lastSent { return false }
        return abs(percent - lastSent) >= threshold || percent == 0 || percent == 100
    }

    private func flush() async {
        flushTask = nil
        guard isEnabled, let percent = pending else { return }
        pending = nil
        if isWorthSending(percent) { await send(percent) }
    }

    private func send(_ percent: Int) async {
        guard isEnabled else { return }
        lastSendTime = clock.now
        let status = await target.status()
        guard status == .running else {
            onUpdate(status, nil)  // Music fermé ou refusé : on ne l'ouvre pas, et on n'enregistre rien
            return
        }
        do {
            try await target.setVolume(percent: percent)
            lastSent = percent
            onUpdate(.running, percent)
        } catch MediaVolumeError.notAuthorized {
            onUpdate(.notAuthorized, nil)
        } catch MediaVolumeError.failed(let message) {
            onUpdate(.failed(message), nil)
        } catch {
            onUpdate(.failed(error.localizedDescription), nil)
        }
    }
}
