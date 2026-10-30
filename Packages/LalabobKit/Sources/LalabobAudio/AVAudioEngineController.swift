import AVFoundation
import CoreAudio
import Foundation
import LalabobModel
import os

public enum AudioEngineError: Error, Equatable, Sendable {
    case notOffline
    case renderFailed
    case outputDeviceUnavailable
}

/// Moteur audio de Lalabob, fondé sur AVAudioEngine.
///
/// Graphe : un `AVAudioPlayerNode` par pad joué → un mélangeur par colonne (le fader)
/// → le mélangeur principal → la sortie choisie.
///
/// Tout l'état vit dans l'acteur ; le thread de rendu audio n'exécute que le code d'Apple.
/// Élagage, fondus et gain des sons courts sont « cuits » dans les échantillons au chargement.
/// Les sons longs sont lus en flux, avec leurs fondus appliqués par le volume du lecteur.
public actor AVAudioEngineController: AudioEngineControlling {
    public enum Output: Sendable {
        /// La sortie audio du Mac.
        case system
        /// Rendu en mémoire, sans carte son (tests).
        case offline(sampleRate: Double, maxFrames: AVAudioFrameCount)
    }

    public nonisolated let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    private let log = Logger(subsystem: "fr.lalabob.app", category: "audio")
    private let engine = AVAudioEngine()
    private let columnMixers: [AVAudioMixerNode]
    private let preloadLimit: TimeInterval

    private struct OfflineRendering {
        let format: AVAudioFormat
        let maxFrames: AVAudioFrameCount
        let buffer: AVAudioPCMBuffer
    }
    private var offline: OfflineRendering?

    private var entries: [Pad.ID: Entry] = [:]
    private var voices: [Pad.ID: Voice] = [:]
    private var nextGeneration = 0
    private var selectedOutputUID: String?
    private var configurationObserver: NSObjectProtocol?

    // MARK: - Types internes

    private enum Source {
        /// Court : tout est en mémoire, fondus et gain compris. `intro` n'existe que pour une boucle avec fondu d'entrée.
        case buffered(intro: AVAudioPCMBuffer?, body: AVAudioPCMBuffer)
        /// Long : lu depuis le disque.
        case streamed(AVAudioFile)
    }

    private struct Entry {
        var column: Int
        var clip: AudioClip
        var timing: ClipTiming
        var format: AVAudioFormat
        var source: Source

        var isStreamed: Bool {
            if case .streamed = source { return true }
            return false
        }
    }

    private final class Voice {
        let player = AVAudioPlayerNode()
        let format: AVAudioFormat
        var state: PlaybackState = .idle
        var generation = 0
        var envelopeTask: Task<Void, Never>?

        init(format: AVAudioFormat) { self.format = format }
    }

    // MARK: - Création

    public init(output: Output = .system, preloadLimit: TimeInterval = 30) {
        (events, continuation) = AsyncStream.makeStream(of: PlaybackEvent.self, bufferingPolicy: .unbounded)
        self.preloadLimit = preloadLimit
        self.columnMixers = (0..<PadGrid.size).map { _ in AVAudioMixerNode() }

        let graphFormat: AVAudioFormat
        if case .offline(let rate, let maxFrames) = output {
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
            do {
                try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maxFrames)
            } catch {
                log.error("Rendu hors ligne impossible : \(error.localizedDescription)")
            }
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maxFrames)!
            offline = OfflineRendering(format: format, maxFrames: maxFrames, buffer: buffer)
            graphFormat = format
        } else {
            graphFormat = engine.outputNode.inputFormat(forBus: 0)
        }
        for mixer in columnMixers {
            engine.attach(mixer)
            engine.connect(mixer, to: engine.mainMixerNode, format: graphFormat)
        }
    }

    // MARK: - AudioEngineControlling

    public func configure(show: Show, audioDirectory: URL) throws {
        observeConfigurationChanges()

        var wanted: [Pad.ID: (column: Int, clip: AudioClip)] = [:]
        for grid in show.grids {
            for (c, column) in grid.columns.enumerated() where column.kind == .audio && c < columnMixers.count {
                for case let pad? in column.slots {
                    if case .audio(let clip) = pad.content { wanted[pad.id] = (c, clip) }
                }
            }
        }

        // Retire ce qui a disparu ou changé.
        for (id, entry) in entries {
            if let new = wanted[id], new.column == entry.column, new.clip == entry.clip { continue }
            dropVoice(id)
            entries[id] = nil
        }
        // Charge ce qui est nouveau. Un fichier illisible n'empêche pas les autres.
        for (id, new) in wanted where entries[id] == nil {
            guard AudioClip.isSafeFileName(new.clip.fileName) else {
                log.error("Nom de fichier refusé : \(new.clip.fileName)")
                continue
            }
            do {
                entries[id] = try load(clip: new.clip, column: new.column, directory: audioDirectory)
            } catch {
                log.error("Son illisible \(new.clip.fileName) : \(error.localizedDescription)")
            }
        }
        try startEngineIfNeeded()
    }

    public func trigger(_ pad: Pad.ID) {
        guard let entry = entries[pad] else { return }
        let state = voices[pad]?.state ?? .idle
        switch RetriggerAction.resolve(state: state, behavior: entry.clip.retrigger) {
        case .start, .restart: startVoice(pad, entry: entry, offset: 0)
        case .stop: stopVoice(pad)
        case .resume: resumeVoice(pad)
        }
    }

    public func togglePause(_ pad: Pad.ID) {
        guard let voice = voices[pad] else { return }
        switch voice.state {
        case .playing(let startedAt):
            voice.player.pause()
            voice.state = .paused(elapsed: ProcessInfo.processInfo.systemUptime - startedAt)
            emit(pad)
        case .paused: resumeVoice(pad)
        case .idle: break
        }
    }

    public func stop(_ pad: Pad.ID) { stopVoice(pad) }

    public func stopAll() {
        for id in Array(voices.keys) { stopVoice(id) }
    }

    public func setColumnLevel(_ column: Int, level: Double) {
        guard columnMixers.indices.contains(column) else { return }
        columnMixers[column].outputVolume = Float(Gain.faderLevel(level))
    }

    public func setOutputDevice(uid: String?) throws {
        selectedOutputUID = uid
        if let uid, AudioOutputDevices.deviceID(forUID: uid) == nil { throw AudioEngineError.outputDeviceUnavailable }
        rebuild()
    }

    // MARK: - Observation

    public func state(of pad: Pad.ID) -> PlaybackState { voices[pad]?.state ?? .idle }

    public func duration(of pad: Pad.ID) -> TimeInterval { entries[pad]?.timing.duration ?? 0 }

    /// Rend `frames` trames en mode hors ligne ; renvoie des échantillons stéréo entrelacés.
    public func renderOffline(frames: Int) async throws -> [Float] {
        guard let offline else { throw AudioEngineError.notOffline }
        // Laisse AVAudioPlayerNode prendre en compte les play() / pause() en attente :
        // sans cela, un départ peut arriver un bloc de rendu trop tard.
        try await Task.sleep(for: .milliseconds(20))
        try startEngineIfNeeded()
        var result: [Float] = []
        result.reserveCapacity(frames * 2)
        var remaining = frames
        while remaining > 0 {
            let count = AVAudioFrameCount(min(remaining, Int(offline.maxFrames)))
            guard try engine.renderOffline(count, to: offline.buffer) == .success,
                let channels = offline.buffer.floatChannelData
            else { throw AudioEngineError.renderFailed }
            for i in 0..<Int(offline.buffer.frameLength) {
                result.append(channels[0][i])
                result.append(channels[1][i])
            }
            remaining -= Int(count)
        }
        return result
    }

    // MARK: - Chargement

    private func load(clip: AudioClip, column: Int, directory: URL) throws -> Entry? {
        let file = try AVAudioFile(forReading: directory.appendingPathComponent(clip.fileName))
        let format = file.processingFormat
        let fileDuration = Double(file.length) / format.sampleRate
        var timing = ClipTiming(clip: clip, fileDuration: fileDuration)
        guard !timing.isEmpty else { return nil }

        guard fileDuration <= preloadLimit else {
            if clip.loops { timing = timing.withoutFadeOut }
            return Entry(column: column, clip: clip, timing: timing, format: format, source: .streamed(file))
        }

        guard let raw = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            return nil
        }
        try file.read(into: raw)
        let source: Source?
        if clip.loops {
            // Le corps de la boucle n'a pas de fondu ; seule la première passe monte en fondu.
            let body = ClipRenderer.bake(raw, timing: timing.withoutFades, gainDB: clip.gainDB)
            let intro = timing.fadeIn > 0 ? ClipRenderer.bake(raw, timing: timing.withoutFadeOut, gainDB: clip.gainDB) : nil
            source = body.map { .buffered(intro: intro, body: $0) }
        } else {
            source = ClipRenderer.bake(raw, timing: timing, gainDB: clip.gainDB).map { .buffered(intro: nil, body: $0) }
        }
        guard let source else { return nil }
        return Entry(column: column, clip: clip, timing: timing, format: format, source: source)
    }

    // MARK: - Voix

    private func voice(for pad: Pad.ID, entry: Entry) -> Voice {
        if let voice = voices[pad], voice.format == entry.format { return voice }
        dropVoice(pad)
        let voice = Voice(format: entry.format)
        engine.attach(voice.player)
        engine.connect(voice.player, to: columnMixers[entry.column], format: entry.format)
        voices[pad] = voice
        return voice
    }

    private func dropVoice(_ pad: Pad.ID) {
        guard let voice = voices.removeValue(forKey: pad) else { return }
        let wasActive = voice.state.isActive
        voice.generation = -1
        voice.envelopeTask?.cancel()
        voice.player.stop()
        engine.detach(voice.player)
        if wasActive { continuation.yield(PlaybackEvent(pad: pad, state: .idle, duration: 0)) }
    }

    private func startVoice(_ pad: Pad.ID, entry: Entry, offset: TimeInterval) {
        do { try startEngineIfNeeded() } catch {
            log.error("Moteur audio indisponible : \(error.localizedDescription)")
            return
        }
        let voice = voice(for: pad, entry: entry)
        nextGeneration += 1
        voice.generation = nextGeneration
        voice.envelopeTask?.cancel()
        voice.player.stop()

        let now = ProcessInfo.processInfo.systemUptime
        voice.state = .playing(startedAt: now - offset)
        voice.player.volume = entry.isStreamed ? Float(entry.timing.envelope(at: offset)) * Gain.linear(fromDB: entry.clip.gainDB) : 1
        schedule(entry, pad: pad, voice: voice, offset: offset)
        voice.player.play()
        if entry.isStreamed, entry.timing.fadeIn > 0 || entry.timing.fadeOut > 0 { runEnvelope(pad, timing: entry.timing, loops: entry.clip.loops, gainDB: entry.clip.gainDB, voice: voice) }
        emit(pad)
    }

    private func resumeVoice(_ pad: Pad.ID) {
        guard let voice = voices[pad], case .paused(let elapsed) = voice.state else { return }
        voice.player.play()
        voice.state = .playing(startedAt: ProcessInfo.processInfo.systemUptime - elapsed)
        emit(pad)
    }

    private func stopVoice(_ pad: Pad.ID) {
        guard let voice = voices[pad], voice.state.isActive else { return }
        nextGeneration += 1
        voice.generation = nextGeneration  // invalide les callbacks de fin en attente
        voice.envelopeTask?.cancel()
        voice.player.stop()
        voice.state = .idle
        emit(pad)
    }

    private func finished(_ pad: Pad.ID, generation: Int) {
        guard let voice = voices[pad], voice.generation == generation, voice.state.isActive else { return }
        voice.envelopeTask?.cancel()
        voice.state = .idle
        emit(pad)
    }

    private func emit(_ pad: Pad.ID) {
        guard let voice = voices[pad] else { return }
        continuation.yield(PlaybackEvent(pad: pad, state: voice.state, duration: entries[pad]?.timing.duration ?? 0))
    }

    // MARK: - Planification

    private func schedule(_ entry: Entry, pad: Pad.ID, voice: Voice, offset: TimeInterval) {
        let generation = voice.generation
        let player = voice.player
        let onEnd: @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void = { [weak self] _ in
            Task { await self?.finished(pad, generation: generation) }
        }

        switch entry.source {
        case .buffered(let intro, let body):
            let rate = body.format.sampleRate
            let offsetFrames = Int(offset * rate)
            if !entry.clip.loops {
                if let rest = ClipRenderer.slice(body, fromFrame: offsetFrames) {
                    player.scheduleBuffer(rest, at: nil, options: [], completionCallbackType: .dataPlayedBack, completionHandler: onEnd)
                } else {
                    Task { self.finished(pad, generation: generation) }
                }
                return
            }
            let length = Int(body.frameLength)
            if let intro, offsetFrames < length, let rest = ClipRenderer.slice(intro, fromFrame: offsetFrames) {
                player.scheduleBuffer(rest, at: nil, options: [], completionHandler: nil)
            } else if length > 0, offsetFrames % length > 0,
                let rest = ClipRenderer.slice(body, fromFrame: offsetFrames % length)
            {
                player.scheduleBuffer(rest, at: nil, options: [], completionHandler: nil)
            }
            player.scheduleBuffer(body, at: nil, options: .loops, completionHandler: nil)

        case .streamed(let file):
            scheduleSegment(of: file, entry: entry, player: player, offset: offset, pad: pad, generation: generation)
        }
    }

    private func scheduleSegment(
        of file: AVAudioFile, entry: Entry, player: AVAudioPlayerNode, offset: TimeInterval, pad: Pad.ID, generation: Int
    ) {
        let rate = file.processingFormat.sampleRate
        let first = AVAudioFramePosition((entry.timing.start + offset) * rate)
        let last = AVAudioFramePosition(entry.timing.end * rate)
        guard last > first else {
            Task { self.finished(pad, generation: generation) }
            return
        }
        player.scheduleSegment(
            file, startingFrame: first, frameCount: AVAudioFrameCount(last - first), at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { await self?.segmentEnded(pad, generation: generation) }
        }
    }

    private func segmentEnded(_ pad: Pad.ID, generation: Int) {
        guard let voice = voices[pad], voice.generation == generation, voice.state.isActive else { return }
        if let entry = entries[pad], entry.clip.loops, case .streamed(let file) = entry.source {
            scheduleSegment(of: file, entry: entry, player: voice.player, offset: 0, pad: pad, generation: generation)
        } else {
            finished(pad, generation: generation)
        }
    }

    /// Fondus d'un son lu en flux : le volume du lecteur suit l'enveloppe, 50 fois par seconde.
    private func runEnvelope(_ pad: Pad.ID, timing: ClipTiming, loops: Bool, gainDB: Double, voice: Voice) {
        let generation = voice.generation
        let gain = Gain.linear(fromDB: gainDB)
        voice.envelopeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                guard let self,
                    await self.updateEnvelope(pad, timing: timing, loops: loops, generation: generation, gain: gain)
                else { return }
            }
        }
    }

    private func updateEnvelope(_ pad: Pad.ID, timing: ClipTiming, loops: Bool, generation: Int, gain: Float) -> Bool {
        guard let voice = voices[pad], voice.generation == generation else { return false }
        guard case .playing(let startedAt) = voice.state else { return true }  // en pause : on attend
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        voice.player.volume = gain * Float(timing.envelope(at: elapsed))
        return elapsed < timing.duration || loops
    }

    // MARK: - Moteur, sortie et reprise

    private func startEngineIfNeeded() throws {
        guard !engine.isRunning else { return }
        applyOutputDevice()
        engine.prepare()
        try engine.start()
    }

    private func applyOutputDevice() {
        guard offline == nil else { return }
        let device = selectedOutputUID.flatMap(AudioOutputDevices.deviceID(forUID:)) ?? AudioOutputDevices.defaultOutputDeviceID()
        guard let device else { return }
        do { try engine.outputNode.auAudioUnit.setDeviceID(device) } catch {
            log.error("Changement de sortie refusé : \(error.localizedDescription)")
        }
    }

    private func observeConfigurationChanges() {
        guard configurationObserver == nil, offline == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            Task { await self?.rebuild() }
        }
    }

    /// Redémarre le moteur (changement ou perte de sortie) et reprend les sons là où ils en étaient.
    private func rebuild() {
        let now = ProcessInfo.processInfo.systemUptime
        let snapshot: [(pad: Pad.ID, elapsed: TimeInterval, paused: Bool)] = voices.compactMap { id, voice in
            switch voice.state {
            case .idle: nil
            case .playing(let startedAt): (id, now - startedAt, false)
            case .paused(let elapsed): (id, elapsed, true)
            }
        }
        for id in Array(voices.keys) {
            guard let voice = voices.removeValue(forKey: id) else { continue }
            voice.generation = -1
            voice.envelopeTask?.cancel()
            voice.player.stop()
            engine.detach(voice.player)
        }
        engine.stop()
        let format = offline?.format ?? engine.outputNode.inputFormat(forBus: 0)
        for mixer in columnMixers {
            engine.disconnectNodeOutput(mixer)
            engine.connect(mixer, to: engine.mainMixerNode, format: format)
        }
        do { try startEngineIfNeeded() } catch {
            log.error("Redémarrage du moteur impossible : \(error.localizedDescription)")
            for item in snapshot { continuation.yield(PlaybackEvent(pad: item.pad, state: .idle, duration: 0)) }
            return
        }
        for item in snapshot {
            guard let entry = entries[item.pad] else { continue }
            startVoice(item.pad, entry: entry, offset: item.elapsed.truncatingRemainder(dividingBy: entry.clip.loops ? max(entry.timing.duration, 0.001) : .infinity))
            if item.paused { togglePause(item.pad) }
        }
    }
}
