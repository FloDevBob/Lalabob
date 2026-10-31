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

    /// Crêtes du signal de chaque colonne, pour les vumètres (lues par l'interface sans attendre le moteur).
    var meters: ColumnMeters { get }

    /// Communique au moteur les sons du spectacle (tous les onglets) et le dossier `Audio/`.
    /// Les sons en cours de lecture ne sont pas interrompus s'ils n'ont pas changé.
    func configure(show: Show, audioDirectory: URL) async throws

    func trigger(_ pad: Pad.ID) async
    func togglePause(_ pad: Pad.ID) async
    func stop(_ pad: Pad.ID) async
    func stopAll() async
    func setColumnLevel(_ column: Int, level: Double) async

    /// Déplace la tête de lecture d'un pad : `elapsed` secondes depuis le début de la partie jouée.
    /// Joue : continue de là ; en pause : reste en pause à cette position ; arrêté : démarre de là.
    func seek(_ pad: Pad.ID, to elapsed: TimeInterval) async

    /// Règle en direct le volume d'un pad (dB), y compris pendant la lecture (jauge de l'inspecteur).
    func setPadGain(_ pad: Pad.ID, gainDB: Double) async

    /// Choisit la sortie audio (`nil` = sortie par défaut du système). Les sons en cours reprennent là où ils en étaient.
    func setOutputDevice(uid: String?) async throws
}

extension AudioEngineControlling {
    /// Un moteur qui ne mesure rien n'allume aucun vumètre.
    public var meters: ColumnMeters { .idle }
}
