import AppKit
import ApplicationServices
import Foundation

/// Règle le volume d'Apple Music par Apple Events (un AppleScript exécuté dans Lalabob, sans Terminal ni `osascript`).
///
/// - Ne **lance jamais** Music : on vérifie qu'il tourne avant chaque envoi (`tell application id` seul le lancerait).
/// - Ne touche à rien d'autre que `sound volume` de Music : ni les pads, ni les colonnes, ni la sortie audio de Lalabob.
/// - Aucun test automatique (il faudrait de vrais Apple Events).
public actor AppleMusicVolume: MediaVolumeControlling {
    private static let bundleIdentifier = "com.apple.Music"

    public init() {}

    private static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty }

    public func status() async -> MediaVolumeStatus {
        guard Self.isRunning else { return .notRunning }
        // Music tourne : macOS demande l'autorisation une seule fois (première utilisation), puis la retient.
        let target = NSAppleEventDescriptor(bundleIdentifier: Self.bundleIdentifier)
        let result = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
        return result == OSStatus(errAEEventNotPermitted) ? .notAuthorized : .running
    }

    public func setVolume(percent: Int) async throws {
        guard Self.isRunning else { return }
        try await run("set sound volume to \(max(0, min(percent, 100)))")
    }

    public func currentVolume() async throws -> Int? {
        guard Self.isRunning else { return nil }
        return try await run("get sound volume")
    }

    /// Exécute une commande AppleScript adressée à Music (sur le fil principal, où vit `NSAppleScript`) ; renvoie le résultat entier s'il y en a un.
    @discardableResult
    private func run(_ command: String) async throws -> Int? {
        let source = "tell application id \"\(Self.bundleIdentifier)\" to \(command)"
        let outcome: (Int?, Int, String) = await MainActor.run {
            var info: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&info)
            guard let info else { return (result.map { Int($0.int32Value) }, 0, "") }
            return (nil, info[NSAppleScript.errorNumber] as? Int ?? 0, info[NSAppleScript.errorMessage] as? String ?? "erreur inconnue")
        }
        let (result, number, message) = outcome
        if number == 0 { return result }
        throw number == -1743 ? MediaVolumeError.notAuthorized : MediaVolumeError.failed("\(message) (\(number))")
    }
}
