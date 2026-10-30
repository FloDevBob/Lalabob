import Foundation
import LalabobModel

/// État de lecture d'un pad audio, tel que l'interface et les LED l'affichent.
public enum PlaybackState: Equatable, Sendable {
    case idle
    /// En lecture depuis `startedAt` (horloge monotone, en secondes).
    case playing(startedAt: TimeInterval)
    /// En pause après `elapsed` secondes de lecture.
    case paused(elapsed: TimeInterval)

    public var isActive: Bool { self != .idle }
}

/// Contrat du moteur audio. L'implémentation AVAudioEngine arrive au jalon 1.
///
/// Règles (voir CLAUDE.md) :
/// - aucune allocation, aucun verrou, aucune E/S sur le thread de rendu audio ;
/// - l'interface envoie des commandes, elle ne touche jamais aux nœuds audio.
public protocol AudioEngineControlling: Sendable {
    func trigger(_ pad: Pad.ID) async
    func togglePause(_ pad: Pad.ID) async
    func stop(_ pad: Pad.ID) async
    func stopAll() async
    func setColumnLevel(_ column: Int, level: Double) async
}
