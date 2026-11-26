import AppKit
import Foundation

/// Accès à l'app Music par AppleScript (`NSAppleScript`, exécuté dans Lalabob) : volume, bibliothèque, lecture.
/// Tout passe par ici : une seule façon d'adresser Music, de traduire ses erreurs et d'échapper le texte.
enum MusicScripting {
    static let bundleIdentifier = "com.apple.Music"

    /// Music tourne-t-il ? Vérifié avant chaque commande : `tell application` seul le lancerait, ce qu'on ne fait jamais.
    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty }

    /// Exécute `body` à l'intérieur de `tell application id "com.apple.Music"` (fil principal, où vit `NSAppleScript`).
    /// −1743 (refus de macOS) → `.notAuthorized` ; toute autre erreur → `.failed` avec le message et le numéro.
    @MainActor
    static func execute(_ body: String) throws -> NSAppleEventDescriptor {
        let source = "tell application id \"\(bundleIdentifier)\"\n\(body)\nend tell"
        var info: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&info)
        if let info {
            let number = info[NSAppleScript.errorNumber] as? Int ?? 0
            let message = info[NSAppleScript.errorMessage] as? String ?? "erreur inconnue"
            throw number == -1743 ? MediaVolumeError.notAuthorized : MediaVolumeError.failed("\(message) (\(number))")
        }
        return result ?? NSAppleEventDescriptor.null()
    }

    /// Un texte placé entre guillemets dans un script : barres obliques inverses et guillemets échappés, caractères de
    /// contrôle retirés. Ce qui vient de l'utilisateur (recherche) ne peut pas sortir de la chaîne.
    static func quoted(_ text: String) -> String {
        let cleaned = String(String.UnicodeScalarView(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
        return "\"" + cleaned.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

extension NSAppleEventDescriptor {
    /// Les éléments d'une liste AppleScript (vide si ce n'est pas une liste).
    var listItems: [NSAppleEventDescriptor] {
        guard descriptorType == typeAEList else { return [] }
        return numberOfItems > 0 ? (1...numberOfItems).compactMap { atIndex($0) } : []
    }

    var text: String { stringValue ?? "" }
}
