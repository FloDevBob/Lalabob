import Foundation
import LalabobModel

public enum AudioImportError: Error, Equatable, Sendable {
    case unsupportedFormat
    case notAFile
    case copyFailed
}

/// Copie les sons dans le dossier de travail d'un spectacle (le futur `Audio/` du paquet).
/// Sur APFS, la copie est un clone : instantanée et sans espace disque supplémentaire.
public enum AudioImporter {
    public static let supportedExtensions: Set<String> = [
        "wav", "wave", "aif", "aiff", "aifc", "caf", "mp3", "m4a", "aac", "flac",
    ]

    public static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Importe `url` dans `library` et renvoie le nom du fichier à mettre dans le pad.
    /// Le même fichier importé deux fois n'est copié qu'une fois ; un autre fichier du même nom reçoit un numéro.
    public static func importFile(at url: URL, into library: URL) throws(AudioImportError) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { throw .notAFile }
        guard isSupported(url) else { throw .unsupportedFormat }

        let manager = FileManager.default
        do { try manager.createDirectory(at: library, withIntermediateDirectories: true) } catch { throw .copyFailed }
        let existing = Set((try? manager.contentsOfDirectory(atPath: library.path)) ?? [])
        let wanted = AudioClip.safeFileName(from: url.lastPathComponent)

        if existing.contains(wanted),
            manager.contentsEqual(atPath: url.path, andPath: library.appending(path: wanted).path)
        {
            return wanted
        }
        let name = AudioClip.uniqueFileName(wanted, avoiding: existing)
        do { try manager.copyItem(at: url, to: library.appending(path: name)) } catch { throw .copyFailed }
        return name
    }

    /// Pad pré-rempli pour un son : titre = nom du fichier, couleur stable choisie d'après ce nom.
    public static func pad(forFileName fileName: String) -> Pad {
        let tints = Tint.allCases.filter { $0 != .blanc && $0 != .graphite }
        // Somme simple et déterministe (`hashValue` change à chaque lancement).
        let index = fileName.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % tints.count
        return Pad(
            title: String((fileName as NSString).deletingPathExtension.prefix(ShowController.maximumTextLength)),
            tint: tints[index],
            content: .audio(clip: AudioClip(fileName: fileName))
        )
    }
}

extension ShowController {
    /// Glisser un fichier son sur une case : copie le son dans le dossier du spectacle et crée le pad (annulable).
    @discardableResult
    public func dropAudioFile(_ url: URL, at position: GridPosition) -> Bool {
        guard let audioDirectory, position.isValid, currentGrid.columns[position.column].kind == .audio else { return false }
        do {
            let name = try AudioImporter.importFile(at: url, into: audioDirectory)
            return place(AudioImporter.pad(forFileName: name), at: position)
        } catch {
            return false
        }
    }
}
