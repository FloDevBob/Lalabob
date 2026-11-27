import Foundation
import Synchronization

/// Sortie DMX réelle : un fil dédié, à haute priorité, envoie la trame en continu (30 Hz par défaut).
///
/// Hors `MainActor` et hors du fil audio : une interface qui rame ne fige pas la lumière, et la lumière ne touche
/// jamais au son. Le moteur pose la trame voulue (`setFrame`) ; le fil en prend une copie à chaque rafraîchissement.
/// L'état partagé est sous un `Mutex`, tenu le temps d'une copie : jamais pendant un envoi.
public final class DMXOutput: DMXTransport {
    public static let defaultRate = 30.0
    /// 44 Hz = une trame complète de 512 canaux ; au-delà, la ligne ne suit plus.
    public static let rateRange = 1.0...44.0
    /// Nombre d'envois de la trame finale à l'arrêt : une trame perdue ne doit pas laisser la lumière allumée.
    public static let finalFrameRepeats = 5

    private struct Shared {
        var frame = DMXFrame()
        var preferredSerial: String?
        var reselect = false
        var status: DMXStatus = .stopped
        var started = false
        var stopRequested = false
        var finalFrame: DMXFrame?
        var finished: [CheckedContinuation<Void, Never>] = []
        var isFinished = false
    }

    public let rate: Double
    private let opener: any SerialLineOpener
    private let writer: OpenDMXWriter
    private let shared = Mutex(Shared())
    public let statusUpdates: AsyncStream<DMXStatus>
    private let continuation: AsyncStream<DMXStatus>.Continuation

    public init(
        opener: any SerialLineOpener = POSIXSerialOpener(), writer: OpenDMXWriter = OpenDMXWriter(),
        rate: Double = DMXOutput.defaultRate
    ) {
        self.opener = opener
        self.writer = writer
        self.rate = min(max(rate, Self.rateRange.lowerBound), Self.rateRange.upperBound)
        (statusUpdates, continuation) = AsyncStream.makeStream(of: DMXStatus.self, bufferingPolicy: .bufferingNewest(8))
    }

    public var status: DMXStatus { shared.withLock { $0.status } }

    public func start() {
        let shouldStart = shared.withLock { s in
            guard !s.started, !s.stopRequested else { return false }
            s.started = true
            return true
        }
        guard shouldStart else { return }
        let thread = Thread { [self] in run() }
        thread.name = "Lalabob DMX"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    public func setFrame(_ frame: DMXFrame) { shared.withLock { $0.frame = frame } }

    public func selectPort(serialNumber: String?) {
        shared.withLock { s in
            guard s.preferredSerial != serialNumber else { return }
            s.preferredSerial = serialNumber
            s.reselect = true
        }
    }

    public func availablePorts() -> [DMXPortInfo] { opener.availablePorts() }

    public func shutdown(finalFrame: DMXFrame?) async {
        let wasRunning = shared.withLock { s in
            s.stopRequested = true
            s.finalFrame = finalFrame
            return s.started && !s.isFinished
        }
        guard wasRunning else {
            publish(.stopped)
            return
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let resumeNow = shared.withLock { s in
                if s.isFinished { return true }
                s.finished.append(c)
                return false
            }
            if resumeNow { c.resume() }
        }
    }

    // MARK: - Fil DMX

    private func run() {
        var loop = DMXRefreshLoop(opener: opener, writer: writer)
        let clock = ContinuousClock()
        let period = Duration.seconds(1 / rate)
        var deadline = clock.now
        while true {
            let snapshot = shared.withLock { s in
                defer { s.reselect = false }
                return (s.frame, s.preferredSerial, s.reselect, s.stopRequested, s.finalFrame)
            }
            let (frame, preferred, reselect, stop, finalFrame) = snapshot
            if stop {
                if let finalFrame {
                    for _ in 0..<Self.finalFrameRepeats {
                        loop.step(frame: finalFrame, preferredSerial: preferred, reselect: false, now: clock.now)
                    }
                }
                loop.close()
                finish()
                return
            }
            if loop.step(frame: frame, preferredSerial: preferred, reselect: reselect, now: clock.now) {
                publish(loop.status)
            }
            deadline += period
            let now = clock.now
            if deadline > now {
                Thread.sleep(forTimeInterval: Self.seconds(deadline - now))
            } else {
                deadline = now  // en retard : on ne rattrape pas en rafale
            }
        }
    }

    private func finish() {
        let waiting = shared.withLock { s in
            s.isFinished = true
            s.status = .stopped
            defer { s.finished = [] }
            return s.finished
        }
        continuation.yield(.stopped)
        for c in waiting { c.resume() }
    }

    private func publish(_ status: DMXStatus) {
        shared.withLock { $0.status = status }
        continuation.yield(status)
    }

    private static func seconds(_ d: Duration) -> TimeInterval {
        let (s, atto) = d.components
        return TimeInterval(s) + TimeInterval(atto) / 1e18
    }
}
