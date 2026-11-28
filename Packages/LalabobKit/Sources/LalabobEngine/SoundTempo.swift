import Foundation
import LalabobAudio
import LalabobModel

/// Ce qui détecte le tempo d'un fichier (hors ligne). Version réelle : `TempoStore` ; tests : un faux.
public protocol TempoAnalyzing: Sendable {
    /// `nil` : fichier illisible, trop court ou sans attaques.
    func tempo(for url: URL) async -> TempoEstimate?
}

/// Tempos détectés une fois puis gardés en mémoire et sur disque (caches de l'app), comme les formes d'onde.
/// La clé tient compte du chemin, de la taille et de la date du fichier : un son remplacé est réanalysé.
public actor TempoStore: TempoAnalyzing {
    public static let shared = TempoStore(
        cacheDirectory: URL.cachesDirectory.appending(path: "Tempos", directoryHint: .isDirectory))

    private struct Cached: Codable {
        var estimate: TempoEstimate?
    }

    private let cacheDirectory: URL
    private var memory: [String: Cached] = [:]

    public init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
    }

    public func tempo(for url: URL) async -> TempoEstimate? {
        guard let key = cacheKey(for: url) else { return nil }
        if let cached = memory[key] { return cached.estimate }
        let file = cacheDirectory.appending(path: key + ".json")
        if let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode(Cached.self, from: data) {
            memory[key] = cached
            return cached.estimate
        }
        // L'analyse lit le fichier : hors de l'acteur, en tâche de fond peu prioritaire.
        let estimate = await Task.detached(priority: .utility) { try? TempoDetector.analyze(url) }.value
        let cached = Cached(estimate: estimate)
        memory[key] = cached
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(cached).write(to: file, options: .atomic)
        return cached.estimate
    }

    private func cacheKey(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
        let stamp = "tempo-v1|\(url.standardizedFileURL.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325  // FNV-1a 64 bits, stable d'un lancement à l'autre
        for byte in stamp.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

/// Le son qui donne le tempo, vu par la console : tempo et instant d'un temps, en `ProcessInfo.systemUptime`.
struct TempoSource: Equatable {
    var bpm: Double
    var beatUptime: Double
}

extension ShowController {
    // MARK: - Détection

    /// Lance l'analyse des sons du spectacle pas encore analysés (en arrière-plan ; chaque résultat arrive seul).
    func analyzeTempos() {
        guard let analyzer = tempoAnalyzer, let audioDirectory else { return }
        for name in show.usedAudioFileNames.sorted() where !tempoRequested.contains(name) {
            tempoRequested.insert(name)
            let url = audioDirectory.appending(path: name)
            Task { [weak self] in
                guard let estimate = await analyzer.tempo(for: url), let self else { return }
                self.detectedTempos[name] = estimate
                self.lightingChangeHandler?()
            }
        }
    }

    /// Tempo détecté du son d'un pad (fiable ou non), `nil` tant qu'il n'est pas analysé.
    public func detectedTempo(for clip: AudioClip) -> TempoEstimate? { detectedTempos[clip.fileName] }

    /// Grille de temps retenue pour un son : la correction à la main, sinon la détection si elle est fiable.
    public func beatGrid(for clip: AudioClip) -> BeatGrid? {
        switch clip.tempo {
        case .none?: return nil
        case .manual(let grid)?: return grid
        case nil:
            guard let estimate = detectedTempos[clip.fileName], estimate.isReliable else { return nil }
            return BeatGrid(bpm: estimate.bpm, firstBeat: estimate.firstBeat)
        }
    }

    // MARK: - Le son qui donne le tempo

    /// Le dernier son **lancé** qui joue (pas en pause) et a un tempo (décision du 27/11/2026) ; s'il s'arrête, le précédent
    /// qui joue encore ; sinon `nil` (tempo de repli de l'alternance). `now` : `ProcessInfo.systemUptime`.
    ///
    /// Les temps se déduisent de la position de lecture : le son est parti (début de la partie élaguée) à `startedAt`.
    /// Pour une boucle, la grille repart à chaque tour (exacte si la boucle dure un nombre entier de temps).
    func tempoSource(atUptime now: Double) -> TempoSource? {
        var best: (order: Int, source: TempoSource)?
        for (id, event) in playback {
            guard case .playing(let startedAt) = event.state, let order = launchOrder[id], order > (best?.order ?? -1),
                let clip = audioClip(withID: id), let grid = beatGrid(for: clip)
            else { continue }
            var start = startedAt
            if clip.loops, event.duration > 0 {
                start += ((now - startedAt) / event.duration).rounded(.down) * event.duration
            }
            best = (order, TempoSource(bpm: grid.bpm, beatUptime: start + grid.firstBeat - clip.trimStart))
        }
        return best?.source
    }

    /// Note l'ordre de lancement des sons (pour `tempoSource`) : un son qui part de l'arrêt prend le rang suivant ; une
    /// reprise après pause garde le sien.
    func noteLaunch(_ event: PlaybackEvent, previous: PlaybackState?) {
        switch event.state {
        case .idle: launchOrder[event.pad] = nil
        case .playing where previous == nil || previous == .idle:
            launchCounter += 1
            launchOrder[event.pad] = launchCounter
        default: break
        }
    }

    private func audioClip(withID id: Pad.ID) -> AudioClip? {
        for grid in show.grids {
            for column in grid.columns {
                for case let pad? in column.slots where pad.id == id { return pad.audio }
            }
        }
        return nil
    }

    // MARK: - Correction à la main (⌘Z, refusée verrouillé)

    /// Remplace le tempo d'un son : `nil` = revenir à la détection, `.none` = pas de tempo, `.manual` = tempo choisi.
    public func setTempo(at position: GridPosition, _ tempo: SoundTempo?) {
        commit("Tempo") { show, grid in
            guard position.isValid, var pad = show.grids[grid][position], var clip = pad.audio, clip.tempo != tempo else {
                return false
            }
            clip.tempo = tempo
            pad.audio = clip
            show.grids[grid][position] = pad
            return true
        }
    }

    /// Tempo × 2 (même premier temps).
    public func doubleTempo(at position: GridPosition) { scaleTempo(at: position, by: 2) }

    /// Tempo ÷ 2 (même premier temps).
    public func halveTempo(at position: GridPosition) { scaleTempo(at: position, by: 0.5) }

    private func scaleTempo(at position: GridPosition, by factor: Double) {
        guard let clip = pad(at: position)?.audio, let grid = beatGrid(for: clip) else { return }
        setTempo(at: position, .manual(BeatGrid(bpm: grid.bpm * factor, firstBeat: grid.firstBeat)))
    }

    /// Nombre d'appuis avant que « Taper le tempo » donne un tempo.
    static let tapsNeeded = 4
    /// Au-delà de cet écart entre deux appuis, on recommence à compter.
    static let tapTimeout = 2.0

    /// « Taper le tempo » : à partir du 4e appui (moins de 2 s entre deux), le tempo devient celui des appuis (médiane des
    /// écarts) ; si le son joue, le dernier appui marque un temps. Renvoie le tempo tapé, `nil` tant qu'il manque des appuis.
    @discardableResult
    public func tapTempo(at position: GridPosition, uptime: Double = ProcessInfo.processInfo.systemUptime) -> Double? {
        guard let pad = pad(at: position), let clip = pad.audio else { return nil }
        if var current = taps, current.position == position, let last = current.times.last, uptime - last < Self.tapTimeout,
            uptime > last
        {
            current.times = Array((current.times + [uptime]).suffix(8))
            taps = current
        } else {
            taps = (position, [uptime])
        }
        guard let times = taps?.times, times.count >= Self.tapsNeeded else { return nil }
        let intervals = zip(times.dropFirst(), times).map { $0 - $1 }.sorted()
        let bpm = 60 / intervals[intervals.count / 2]
        var firstBeat = beatGrid(for: clip)?.firstBeat ?? clip.trimStart
        if case .playing(let startedAt)? = playback[pad.id]?.state {
            var elapsed = uptime - startedAt
            if clip.loops, let duration = playback[pad.id]?.duration, duration > 0 {
                elapsed = elapsed.truncatingRemainder(dividingBy: duration)
            }
            firstBeat = clip.trimStart + elapsed
        }
        let grid = BeatGrid(bpm: bpm, firstBeat: firstBeat)
        setTempo(at: position, .manual(grid))
        return grid.bpm
    }
}
