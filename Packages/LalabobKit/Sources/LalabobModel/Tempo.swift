import Foundation

// Tempo des sons (J14, étape 3b) : la grille de temps d'un son, pour caler l'alternance lumineuse sur la musique.
// La détection (hors ligne, `LalabobAudio`) n'est pas enregistrée dans le spectacle : elle est recalculée et gardée en
// cache. Seule la **correction à la main** l'est (`AudioClip.tempo`).

/// Grille de temps d'un son : tempo et instant d'un temps (de préférence le premier temps d'une mesure), en secondes
/// depuis le début du **fichier**.
public struct BeatGrid: Codable, Sendable, Equatable, Hashable {
    public static let bpmRange = 30.0...300.0

    public var bpm: Double
    public var firstBeat: TimeInterval

    /// Tempo borné à 30…300, premier temps ramené dans la première période (positif).
    public init(bpm: Double, firstBeat: TimeInterval) {
        let bpm = bpm.isFinite ? min(max(bpm, Self.bpmRange.lowerBound), Self.bpmRange.upperBound) : 120
        let period = 60 / bpm
        var first = firstBeat.isFinite ? firstBeat.truncatingRemainder(dividingBy: period) : 0
        if first < 0 { first += period }
        self.bpm = bpm
        self.firstBeat = first
    }

    /// Durée d'un temps, en secondes.
    public var beatPeriod: TimeInterval { 60 / bpm }

    var isValid: Bool { bpm.isFinite && Self.bpmRange.contains(bpm) && firstBeat.isFinite && firstBeat >= 0 && firstBeat < 86_400 }

    private enum CodingKeys: String, CodingKey { case bpm, firstBeat }

    /// Sans correction : un fichier hors bornes est refusé par `Show.validate()`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bpm = try c.decode(Double.self, forKey: .bpm)
        firstBeat = try c.decode(Double.self, forKey: .firstBeat)
    }
}

/// Tempo d'un son corrigé à la main. Absent (`nil` dans `AudioClip.tempo`) = celui de la détection.
public enum SoundTempo: Codable, Sendable, Equatable {
    /// « Pas de tempo » : l'alternance n'utilise pas ce son.
    case none
    /// Tempo et premier temps choisis (×2, ÷2, taper le tempo…).
    case manual(BeatGrid)

    private enum Kind: String, Codable { case none, manual }
    private enum CodingKeys: String, CodingKey { case type, grid }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .none: self = .none
        case .manual: self = .manual(try c.decode(BeatGrid.self, forKey: .grid))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none: try c.encode(Kind.none, forKey: .type)
        case .manual(let grid):
            try c.encode(Kind.manual, forKey: .type)
            try c.encode(grid, forKey: .grid)
        }
    }
}
