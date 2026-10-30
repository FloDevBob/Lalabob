import Foundation
import LalabobModel

/// État de lecture d'un pad audio, tel que l'interface et les LED l'affichent.
public enum PlaybackState: Equatable, Sendable {
    case idle
    /// En lecture ; le temps écoulé vaut `ProcessInfo.systemUptime - startedAt` (horloge monotone, en secondes).
    case playing(startedAt: TimeInterval)
    /// En pause après `elapsed` secondes de lecture.
    case paused(elapsed: TimeInterval)

    public var isActive: Bool { self != .idle }
}

/// Changement d'état d'un pad, émis par le moteur.
public struct PlaybackEvent: Equatable, Sendable {
    public var pad: Pad.ID
    public var state: PlaybackState
    /// Durée utile de l'extrait (après élagage), pour la barre de progression.
    public var duration: TimeInterval

    public init(pad: Pad.ID, state: PlaybackState, duration: TimeInterval) {
        self.pad = pad
        self.state = state
        self.duration = duration
    }
}

/// Contrat du moteur audio.
///
/// Règles (voir CLAUDE.md) :
/// - aucune allocation, aucun verrou, aucune E/S sur le thread de rendu audio ;
/// - l'interface envoie des commandes, elle ne touche jamais aux nœuds audio.
public protocol AudioEngineControlling: Sendable {
    /// Flux des changements d'état de lecture.
    var events: AsyncStream<PlaybackEvent> { get }

    /// Communique au moteur les sons du spectacle (tous les onglets) et le dossier `Audio/`.
    /// Les sons en cours de lecture ne sont pas interrompus s'ils n'ont pas changé.
    func configure(show: Show, audioDirectory: URL) async throws

    func trigger(_ pad: Pad.ID) async
    func togglePause(_ pad: Pad.ID) async
    func stop(_ pad: Pad.ID) async
    func stopAll() async
    func setColumnLevel(_ column: Int, level: Double) async

    /// Choisit la sortie audio (`nil` = sortie par défaut du système). Les sons en cours reprennent là où ils en étaient.
    func setOutputDevice(uid: String?) async throws
}
