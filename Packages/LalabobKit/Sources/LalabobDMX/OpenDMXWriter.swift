import Darwin

/// Fabrique le signal DMX sur un boîtier « de type Open DMX » (puce FTDI sans microprogramme DMX) :
/// break, mark after break, puis code de départ et canaux.
public struct OpenDMXWriter: Sendable {
    /// Break ≥ 88 µs (norme) ; 120 µs essayés sur la barre de la troupe.
    public static let breakDuration: Duration = .microseconds(120)
    /// Mark after break ≥ 8 µs ; 16 µs essayés.
    public static let markAfterBreak: Duration = .microseconds(16)

    /// Attente courte entre les étapes. Les tests passent une version qui note sans attendre.
    let pause: @Sendable (Duration) -> Void

    public init(pause: @escaping @Sendable (Duration) -> Void = OpenDMXWriter.sleep) {
        self.pause = pause
    }

    /// Envoie une trame complète et attend qu'elle soit partie (avant le break suivant).
    public func send(_ frame: DMXFrame, on line: any SerialLine) throws {
        try line.setBreak(true)
        pause(Self.breakDuration)
        try line.setBreak(false)
        pause(Self.markAfterBreak)
        try line.write(frame.packet)
        try line.drain()
    }

    public static let sleep: @Sendable (Duration) -> Void = { duration in
        let (seconds, attoseconds) = duration.components
        _ = usleep(useconds_t(seconds * 1_000_000 + attoseconds / 1_000_000_000_000))
    }
}
