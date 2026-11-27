import Foundation
import Synchronization

/// Tampon circulaire stéréo entre deux fils temps réel : un seul **écrivain** (la capture du son de Music) et un seul **lecteur**
/// (le rendu du moteur). Mémoire réservée à la création ; ni verrou ni allocation ensuite. Voir ADR 0011.
///
/// - Le lecteur attend d'avoir `latencyFrames` d'avance avant de rendre du son (amorçage), puis rend du silence s'il manque
///   d'échantillons ; s'il a plus de 3 × `latencyFrames` d'avance (horloges qui dérivent), il saute en avant.
/// - Gain de sortie lissé : `setGain(_:over:)` fait glisser le gain échantillon par échantillon (fondus sans clics).
public final class AudioRingBuffer: @unchecked Sendable {
    public let capacity: Int
    public let latencyFrames: Int
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)
    /// Uptime (ms) de la dernière écriture : la capture vit-elle encore ?
    private let lastWriteMillis = Atomic<Int>(0)
    /// Uptime (ms) du dernier échantillon non nul écrit : un son capté qui reste muet (morceau protégé ?) se repère.
    private let lastSoundMillis = Atomic<Int>(0)
    private let targetGainBits = Atomic<UInt32>(Float(1).bitPattern)
    private let rampFramesLeft = Atomic<Int>(0)
    /// Le gain courant n'est lu et écrit que par le lecteur.
    private var currentGain: Float = 1
    private var primed = false

    public init(capacity: Int = 16_384, latencyFrames: Int = 2_048) {
        self.capacity = capacity
        self.latencyFrames = min(latencyFrames, capacity / 4)
        left = .allocate(capacity: capacity)
        right = .allocate(capacity: capacity)
        left.initialize(repeating: 0, count: capacity)
        right.initialize(repeating: 0, count: capacity)
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    // MARK: Écrivain (fil de capture)

    /// Écrit `frames` trames. `stride` : écart entre deux échantillons d'un même canal (2 pour un tampon entrelacé).
    /// Si le lecteur ne suit pas, les trames qui ne tiennent pas sont abandonnées.
    public func write(left source: UnsafePointer<Float>, right sourceRight: UnsafePointer<Float>, frames: Int, stride: Int = 1) {
        let write = writeIndex.load(ordering: .relaxed)
        let read = readIndex.load(ordering: .acquiring)
        let room = capacity - (write - read)
        let count = min(frames, max(room, 0))
        var loudest: Float = 0
        for i in 0..<count {
            let slot = (write + i) % capacity
            left[slot] = source[i * stride]
            right[slot] = sourceRight[i * stride]
            loudest = max(loudest, abs(left[slot]), abs(right[slot]))
        }
        writeIndex.store(write + count, ordering: .releasing)
        let now = Int(ProcessInfo.processInfo.systemUptime * 1000)
        lastWriteMillis.store(now, ordering: .relaxed)
        if loudest > 1e-5 { lastSoundMillis.store(now, ordering: .relaxed) }
    }

    /// Trames déjà lues (diagnostic et tests : le lecteur avance-t-il ?).
    public var framesRead: Int { readIndex.load(ordering: .relaxed) }

    /// Depuis combien de secondes rien n'a été écrit (`.infinity` si jamais).
    public var secondsSinceLastWrite: TimeInterval {
        let millis = lastWriteMillis.load(ordering: .relaxed)
        guard millis > 0 else { return .infinity }
        return ProcessInfo.processInfo.systemUptime - Double(millis) / 1000
    }

    /// Depuis combien de secondes le son capté est resté muet (`.infinity` s'il ne l'a jamais été… pas encore).
    public var secondsSinceLastSound: TimeInterval {
        let millis = lastSoundMillis.load(ordering: .relaxed)
        guard millis > 0 else { return .infinity }
        return ProcessInfo.processInfo.systemUptime - Double(millis) / 1000
    }

    // MARK: Gain (n'importe quel fil)

    /// Fait glisser le gain de sortie vers `gain` (0…1) en `frames` trames (0 = tout de suite).
    public func setGain(_ gain: Float, overFrames frames: Int) {
        targetGainBits.store(max(0, min(gain, 4)).bitPattern, ordering: .relaxed)
        rampFramesLeft.store(max(0, frames), ordering: .releasing)
    }

    // MARK: Lecteur (fil de rendu)

    /// Fraction de trame entre deux échantillons (lecture à vitesse ajustée) : lue et écrite par le lecteur seul.
    private var fraction: Double = 0
    private let underrunCount = Atomic<Int>(0)
    private let skipCount = Atomic<Int>(0)

    /// Coupures (le tampon s'est vidé) et sauts (trop d'avance rattrapée d'un coup) depuis la création : chacun s'entend.
    public var underruns: Int { underrunCount.load(ordering: .relaxed) }
    public var skips: Int { skipCount.load(ordering: .relaxed) }

    /// Remplit `frames` trames, gain appliqué. Pour rattraper la dérive entre l'horloge de la capture et celle de la sortie, la
    /// lecture va un tout petit peu plus vite quand le tampon se remplit, plus lentement quand il se vide (au plus ±1 %,
    /// interpolation linéaire) : pas de saut, donc pas de clic. Saut franc seulement au-delà de 4 × l'avance voulue.
    public func read(left destination: UnsafeMutablePointer<Float>, right destinationRight: UnsafeMutablePointer<Float>, frames: Int) {
        var read = readIndex.load(ordering: .relaxed)
        let write = writeIndex.load(ordering: .acquiring)
        var available = write - read
        if !primed { primed = available >= latencyFrames }
        if primed, available > 4 * latencyFrames {
            read = write - latencyFrames
            available = latencyFrames
            fraction = 0
            skipCount.add(1, ordering: .relaxed)
        }
        // Vitesse de lecture : 1 quand l'avance est juste, jusqu'à ±1 % quand elle s'en écarte.
        let error = Double(available - latencyFrames) / Double(max(latencyFrames, 1))
        let ratio = 1 + max(-0.01, min(0.01, error * 0.01))
        let target = Float(bitPattern: targetGainBits.load(ordering: .relaxed))
        var rampLeft = rampFramesLeft.load(ordering: .acquiring)
        var position = fraction  // relative à `read`
        var ranDry = false
        for i in 0..<frames {
            if rampLeft > 0 {
                currentGain += (target - currentGain) / Float(rampLeft)
                rampLeft -= 1
            } else {
                currentGain = target
            }
            let whole = Int(position)
            let frac = Float(position - Double(whole))
            // Il faut l'échantillon courant, et le suivant s'il y a une fraction à interpoler.
            guard primed, whole + (frac > 0 ? 1 : 0) < available else {
                destination[i] = 0
                destinationRight[i] = 0
                ranDry = primed
                continue
            }
            let slot = (read + whole) % capacity
            var l = left[slot]
            var r = right[slot]
            if frac > 0 {
                let next = (slot + 1) % capacity
                l += (left[next] - l) * frac
                r += (right[next] - r) * frac
            }
            destination[i] = l * currentGain
            destinationRight[i] = r * currentGain
            position += ratio
        }
        rampFramesLeft.store(rampLeft, ordering: .relaxed)
        let consumed = min(Int(position), available)
        fraction = position - Double(consumed)
        if ranDry {
            underrunCount.add(1, ordering: .relaxed)
            primed = false  // tampon vide : on attend de nouveau l'avance voulue
            fraction = 0
        }
        readIndex.store(read + consumed, ordering: .releasing)
    }
}
