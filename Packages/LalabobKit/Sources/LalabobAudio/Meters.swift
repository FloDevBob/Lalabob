import Foundation
import LalabobModel
import Synchronization

/// Une crête mesurée (amplitude linéaire), lisible et modifiable sans verrou depuis n'importe quel thread.
private final class PeakCell: Sendable {
    private let bits = Atomic<UInt32>(0)

    func store(_ peak: Float) { bits.store(peak.bitPattern, ordering: .relaxed) }
    func load() -> Float { Float(bitPattern: bits.load(ordering: .relaxed)) }
}

/// Crêtes du signal de chaque colonne (gauche et droite), mesurées dans le moteur audio après le fader de colonne.
///
/// Le moteur écrit (`record`), l'interface lit (`peak`) : aucun verrou, aucune allocation après la création,
/// seulement des opérations atomiques sur des entiers. La valeur est la crête du dernier bloc mesuré ; la
/// balistique d'affichage (descente progressive) est faite par l'interface, avec `MeterBallistics`.
public final class ColumnMeters: Sendable {
    public static let channelCount = 2
    /// Moteur muet : tout reste à zéro.
    public static let idle = ColumnMeters()

    private let columns: Int
    private let cells: [PeakCell]

    public init(columns: Int = PadGrid.size) {
        self.columns = columns
        self.cells = (0..<(columns * Self.channelCount)).map { _ in PeakCell() }
    }

    private func cell(column: Int, channel: Int) -> PeakCell? {
        guard (0..<columns).contains(column), (0..<Self.channelCount).contains(channel) else { return nil }
        return cells[column * Self.channelCount + channel]
    }

    /// Enregistre la crête d'un bloc (appelé par le moteur, jamais par l'interface).
    public func record(column: Int, channel: Int, peak: Float) {
        cell(column: column, channel: channel)?.store(peak.isFinite ? max(peak, 0) : 0)
    }

    public func peak(column: Int, channel: Int) -> Float {
        cell(column: column, channel: channel)?.load() ?? 0
    }

    /// La crête la plus forte des deux canaux.
    public func peak(column: Int) -> Float {
        max(peak(column: column, channel: 0), peak(column: column, channel: 1))
    }

    /// Remet tout à zéro (moteur arrêté ou redémarré : plus de signal, plus de barre figée).
    public func reset() {
        for cell in cells { cell.store(0) }
    }
}

/// Descente d'un vumètre à l'écran : montée immédiate, descente à vitesse fixe. Pure et testable.
public enum MeterBallistics {
    /// Fraction de hauteur perdue par seconde (0,45 : de haut en bas en un peu plus de 2 s).
    public static let fallPerSecond = 0.45

    /// Nouvelle position affichée, entre 0 et 1. `target` : position de la crête mesurée (`Gain.meterFraction`).
    public static func next(displayed: Double, target: Double, elapsed: Double) -> Double {
        let target = min(max(target.isFinite ? target : 0, 0), 1)
        if target >= displayed { return target }
        guard elapsed.isFinite, elapsed > 0 else { return displayed }
        return max(target, displayed - fallPerSecond * elapsed)
    }
}

extension Gain {
    /// Plage affichée par le vumètre : de −60 dB (bas) à 0 dB (haut).
    public static let meterRangeDB: ClosedRange<Double> = -60...0

    /// Position 0…1 d'une crête (amplitude linéaire) sur le vumètre ; tout ce qui dépasse 0 dB reste en haut.
    public static func meterFraction(forPeak peak: Float) -> Double {
        guard peak.isFinite, peak > 0 else { return 0 }
        let db = 20 * log10(Double(peak))
        let range = meterRangeDB
        return min(max((db - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }
}
