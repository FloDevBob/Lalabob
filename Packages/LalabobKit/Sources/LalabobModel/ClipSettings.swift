import Foundation

extension AudioClip {
    /// Durée minimale de la partie jouée après élagage.
    public static let minimumLength: TimeInterval = 0.05
    /// Fondu le plus long accepté (même limite que `Show.validate()`).
    public static let maximumFade: TimeInterval = 600
    /// Plage du volume propre au pad, en dB, proposée par l'inspecteur (`Show.validate()` accepte −60…24).
    public static let gainRange: ClosedRange<Double> = -60...12

    /// Élagage borné au fichier : début ≥ 0, fin ≥ début + `minimumLength`, fin du fichier → pas de fin (`nil`).
    /// Les poignées de la forme d'onde ne peuvent donc ni se croiser ni sortir du son.
    public func trimmed(start: TimeInterval, end: TimeInterval, fileDuration: TimeInterval) -> AudioClip {
        let total = fileDuration.isFinite ? max(fileDuration, 0) : 0
        let safeStart = min(max(start.isFinite ? start : 0, 0), max(total - Self.minimumLength, 0))
        let safeEnd = min(max(end.isFinite ? end : total, safeStart + Self.minimumLength), total)
        var copy = self
        copy.trimStart = safeStart
        copy.trimEnd = safeEnd >= total - 1e-6 ? nil : safeEnd
        return copy
    }

    /// Volume propre au pad, borné à `gainRange` et arrondi au dixième de dB ; une valeur non numérique donne 0 dB.
    public func withGain(_ decibels: Double) -> AudioClip {
        var copy = self
        if decibels.isNaN {
            copy.gainDB = 0
        } else {
            let clamped = min(max(decibels, Self.gainRange.lowerBound), Self.gainRange.upperBound)
            copy.gainDB = (clamped * 10).rounded() / 10
        }
        return copy
    }

    /// Position de lecture (secondes depuis le début de la partie jouée) correspondant à un point de la forme d'onde,
    /// donné en secondes dans le fichier. Bornée à la partie élaguée, avec au moins `minimumLength` avant la fin.
    /// Entrée invalide (non numérique, durée nulle…) : début de la partie jouée.
    public func playbackOffset(atFileTime fileTime: TimeInterval, fileDuration: TimeInterval) -> TimeInterval {
        guard fileTime.isFinite, fileDuration.isFinite, fileDuration > 0 else { return 0 }
        let start = min(max(trimStart, 0), fileDuration)
        let end = min(trimEnd ?? fileDuration, fileDuration)
        let usable = max(end - start, 0)
        return min(max(fileTime - start, 0), max(usable - Self.minimumLength, 0))
    }

    /// Fondus bornés à 0…`maximumFade` ; une durée nulle ou négative supprime le fondu.
    public func withFades(in fadeIn: TimeInterval, out fadeOut: TimeInterval) -> AudioClip {
        func clamp(_ value: TimeInterval) -> TimeInterval? {
            guard value.isFinite, value > 0 else { return nil }
            return min(value, Self.maximumFade)
        }
        var copy = self
        copy.fadeIn = clamp(fadeIn)
        copy.fadeOut = clamp(fadeOut)
        return copy
    }
}

extension Show {
    /// Valide un extrait seul, comme le ferait `validate()` à l'ouverture (tests).
    static func validatePad(_ clip: AudioClip) throws(ShowValidationError) {
        try Pad(title: "test", tint: .rouge, content: .audio(clip: clip)).validate()
    }
}
