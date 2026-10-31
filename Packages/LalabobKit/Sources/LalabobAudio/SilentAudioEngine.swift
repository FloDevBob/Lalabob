import Foundation
import LalabobModel

/// Moteur qui ne joue rien : pour les aperçus SwiftUI et les tests de l'orchestration.
public actor SilentAudioEngine: AudioEngineControlling {
    public nonisolated let events: AsyncStream<PlaybackEvent>

    public init() {
        events = AsyncStream { _ in }
    }

    public func configure(show: Show, audioDirectory: URL) {}
    public func trigger(_ pad: Pad.ID) {}
    public func togglePause(_ pad: Pad.ID) {}
    public func stop(_ pad: Pad.ID) {}
    public func stopAll() {}
    public func setColumnLevel(_ column: Int, level: Double) {}
    public func setOutputDevice(uid: String?) {}
    public func setPadGain(_ pad: Pad.ID, gainDB: Double) {}
    public func seek(_ pad: Pad.ID, to elapsed: TimeInterval) {}
}
