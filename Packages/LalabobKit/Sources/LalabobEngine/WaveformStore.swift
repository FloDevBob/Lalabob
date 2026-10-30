import Foundation
import LalabobAudio
import LalabobModel

/// Formes d'onde calculées une fois puis gardées en mémoire et sur disque (caches de l'app).
/// La clé tient compte du chemin, de la taille et de la date du fichier : un son remplacé est recalculé.
public actor WaveformStore {
    public static let shared = WaveformStore(
        cacheDirectory: URL.cachesDirectory.appending(path: "Formes d'onde", directoryHint: .isDirectory))

    private let cacheDirectory: URL
    private var memory: [String: Waveform] = [:]

    public init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
    }

    public func waveform(for url: URL, buckets: Int) throws -> Waveform {
        let key = try cacheKey(for: url, buckets: buckets)
        if let cached = memory[key] { return cached }
        let file = cacheDirectory.appending(path: key + ".json")
        if let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode(Waveform.self, from: data) {
            memory[key] = cached
            return cached
        }
        let waveform = try Waveform.analyze(url, buckets: buckets)
        memory[key] = waveform
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(waveform).write(to: file, options: .atomic)
        return waveform
    }

    private func cacheKey(for url: URL, buckets: Int) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let stamp = "\(url.standardizedFileURL.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(buckets)"
        // FNV-1a 64 bits : stable d'un lancement à l'autre (contrairement à `hashValue`).
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in stamp.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

extension ShowController {
    // MARK: - Réglages audio (inspecteur)

    /// Élagage borné au fichier (`fileDuration` : durée lue sur la forme d'onde).
    public func setTrim(at position: GridPosition, start: TimeInterval, end: TimeInterval, fileDuration: TimeInterval) {
        updateClip(at: position, actionName: "Élaguer") { $0 = $0.trimmed(start: start, end: end, fileDuration: fileDuration) }
    }

    public func setFades(at position: GridPosition, in fadeIn: TimeInterval, out fadeOut: TimeInterval) {
        updateClip(at: position, actionName: "Fondus") { $0 = $0.withFades(in: fadeIn, out: fadeOut) }
    }

    public func setLoops(at position: GridPosition, _ loops: Bool) {
        updateClip(at: position, actionName: "Boucle") { $0.loops = loops }
    }

    public func setRetrigger(at position: GridPosition, _ behavior: RetriggerBehavior) {
        updateClip(at: position, actionName: "Nouvel appui") { $0.retrigger = behavior }
    }

    private func updateClip(at position: GridPosition, actionName: String, _ change: (inout AudioClip) -> Void) {
        commit(actionName) { show, grid in
            guard position.isValid, var pad = show.grids[grid][position], case .audio(var clip) = pad.content else {
                return false
            }
            change(&clip)
            pad.content = .audio(clip: clip)
            show.grids[grid][position] = pad
            return true
        }
    }

    /// Forme d'onde du son d'un pad (`nil` si le fichier est absent ou illisible).
    public func waveform(for clip: AudioClip, buckets: Int = 600) async -> Waveform? {
        guard let audioDirectory else { return nil }
        return try? await WaveformStore.shared.waveform(for: audioDirectory.appending(path: clip.fileName), buckets: buckets)
    }
}
