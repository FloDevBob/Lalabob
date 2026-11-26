import AppKit
import ApplicationServices
import Foundation

/// Règle le volume d'Apple Music par Apple Events (un AppleScript exécuté dans Lalabob, sans Terminal ni `osascript`).
///
/// - Ne **lance jamais** Music : on vérifie qu'il tourne avant chaque envoi (`tell application id` seul le lancerait).
/// - Ne touche à rien d'autre que `sound volume` de Music : ni les pads, ni les colonnes, ni la sortie audio de Lalabob.
/// - Aucun test automatique (il faudrait de vrais Apple Events).
public actor AppleMusicVolume: MediaVolumeControlling {
    public init() {}

    public func status() async -> MediaVolumeStatus {
        guard MusicScripting.isRunning else { return .notRunning }
        // Music tourne : macOS demande l'autorisation une seule fois (première utilisation), puis la retient.
        let target = NSAppleEventDescriptor(bundleIdentifier: MusicScripting.bundleIdentifier)
        let result = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
        return result == OSStatus(errAEEventNotPermitted) ? .notAuthorized : .running
    }

    public func setVolume(percent: Int) async throws {
        guard MusicScripting.isRunning else { return }
        let value = max(0, min(percent, 100))
        try await MainActor.run { _ = try MusicScripting.execute("set sound volume to \(value)") }
    }

    public func currentVolume() async throws -> Int? {
        guard MusicScripting.isRunning else { return nil }
        return try await MainActor.run { Int(try MusicScripting.execute("get sound volume").int32Value) }
    }
}
