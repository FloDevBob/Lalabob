import Foundation
import LalabobModel

/// Les durées utiles d'un extrait une fois l'élagage et les fondus ramenés à des valeurs sûres.
///
/// Les réglages viennent d'un fichier : on les borne ici plutôt que de leur faire confiance.
public struct ClipTiming: Equatable, Sendable {
    /// Début et fin de la partie jouée, en secondes dans le fichier.
    public let start: TimeInterval
    public let end: TimeInterval
    /// Fondus, réduits proportionnellement s'ils dépassent la durée utile.
    public let fadeIn: TimeInterval
    public let fadeOut: TimeInterval

    public init(clip: AudioClip, fileDuration: TimeInterval) {
        let total = fileDuration.isFinite ? max(fileDuration, 0) : 0
        let start = min(max(clip.trimStart.isFinite ? clip.trimStart : 0, 0), total)
        let requestedEnd = clip.trimEnd.flatMap { $0.isFinite ? $0 : nil } ?? total
        let end = min(max(requestedEnd, start), total)

        var fadeIn = max(clip.fadeIn ?? 0, 0)
        var fadeOut = max(clip.fadeOut ?? 0, 0)
        let duration = end - start
        if fadeIn + fadeOut > duration, fadeIn + fadeOut > 0 {
            let scale = duration / (fadeIn + fadeOut)
            fadeIn *= scale
            fadeOut *= scale
        }
        self.start = start
        self.end = end
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
    }

    /// Durée de la partie jouée.
    public var duration: TimeInterval { end - start }

    /// Rien à jouer (début d'élagage au-delà de la fin du fichier, par exemple).
    public var isEmpty: Bool { duration <= 0 }

    /// Même élagage, sans fondu de sortie (une boucle ne se termine pas d'elle-même).
    public var withoutFadeOut: ClipTiming {
        ClipTiming(start: start, end: end, fadeIn: fadeIn, fadeOut: 0)
    }

    /// Même élagage, sans aucun fondu.
    public var withoutFades: ClipTiming {
        ClipTiming(start: start, end: end, fadeIn: 0, fadeOut: 0)
    }

    private init(start: TimeInterval, end: TimeInterval, fadeIn: TimeInterval, fadeOut: TimeInterval) {
        self.start = start
        self.end = end
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
    }

    /// Enveloppe (0…1) à l'instant `t`, en secondes depuis le début de la partie jouée.
    public func envelope(at t: TimeInterval) -> Double {
        var gain = 1.0
        if fadeIn > 0 { gain = min(gain, min(max(t / fadeIn, 0), 1)) }
        if fadeOut > 0 { gain = min(gain, min(max((duration - t) / fadeOut, 0), 1)) }
        return gain
    }
}
