import AppKit
import ApplicationServices
import Foundation
import ScriptingBridge

/// Règle le volume d'Apple Music par Apple Events (ScriptingBridge), sans script ni Terminal.
///
/// - Ne **lance jamais** Music : `isRunning` est vérifié avant chaque envoi (`status()`).
/// - Ne touche à rien d'autre que `sound volume` de Music : ni les pads, ni les colonnes, ni la sortie audio de Lalabob.
/// - `SBApplication` n'est pas `Sendable` : elle reste dans cet acteur. Aucun test automatique (il faudrait de vrais Apple Events).
public actor AppleMusicVolume: MediaVolumeControlling {
    private static let bundleIdentifier = "com.apple.Music"
    private var application: SBApplication?

    public init() {}

    public func status() async -> MediaVolumeStatus {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty else { return .notRunning }
        // Music tourne : macOS demande l'autorisation une seule fois (première utilisation), puis la retient.
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: Self.bundleIdentifier)
        let result = AEDeterminePermissionToAutomateTarget(descriptor.aeDesc, typeWildCard, typeWildCard, true)
        return result == noErr ? .running : (result == OSStatus(errAEEventNotPermitted) ? .notAuthorized : .running)
    }

    public func setVolume(percent: Int) async throws {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty else { return }
        if application == nil { application = SBApplication(bundleIdentifier: Self.bundleIdentifier) }
        guard let application, application.isRunning else { return }
        application.setValue(max(0, min(percent, 100)), forKey: "soundVolume")
        if let error = application.lastError() { throw error }
    }
}
