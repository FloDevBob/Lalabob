import Accelerate
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
/// Élagage et fondus des sons courts sont « cuits » dans les échantillons au chargement.
/// Le volume du pad, lui, passe par un nœud de gain propre à chaque voix : il se règle en direct, même en lecture,
/// et peut dépasser 0 dB (jusqu'à +12 dB) ce que le volume d'un lecteur (0…1) ne permet pas.
/// Les sons longs sont lus en flux, avec leurs fondus appliqués par le volume du lecteur.
public actor AVAudioEngineController: AudioEngineControlling {
    public enum Output: Sendable {
        /// La sortie audio du Mac.
        case system
        /// Rendu en mémoire, sans carte son (tests).
        case offline(sampleRate: Double, maxFrames: AVAudioFrameCount)
    }

    public nonisolated let events: AsyncStream<PlaybackEvent>
    public nonisolated let meters = ColumnMeters()
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
        /// Gain du pad (dB) : un seul réglage global, aucune bande d'égalisation active.
        let gainNode: AVAudioUnitEQ = {
            let node = AVAudioUnitEQ(numberOfBands: 1)
            node.bands[0].bypass = true
            return node
        }()
        let format: AVAudioFormat
        var state: PlaybackState = .idle
        var generation = 0
        var envelopeTask: Task<Void, Never>?
        /// Rendu hors ligne : fondu d'arrêt en cours, compté en secondes de son rendu (pas en temps réel).
        var offlineFade: (startVolume: Float, elapsed: TimeInterval)?

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
        Self.installMeters(on: columnMixers, meters: meters)
    }

    /// Une prise de mesure sur la sortie de chaque mélangeur de colonne (donc après son fader) : la crête de chaque bloc
    /// va dans `meters`. La prise n'est pas le thread de rendu, mais elle reste légère : un `vDSP_maxmgv` par canal,
    /// une écriture atomique, ni allocation ni verrou.
    private static func installMeters(on columnMixers: [AVAudioMixerNode], meters: ColumnMeters) {
        for (column, mixer) in columnMixers.enumerated() {
            mixer.removeTap(onBus: 0)
            mixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
                guard let data = buffer.floatChannelData else { return }
                let frames = vDSP_Length(buffer.frameLength)
                let channels = Int(buffer.format.channelCount)
                for channel in 0..<ColumnMeters.channelCount {
                    var peak: Float = 0
                    // Un son mono est entendu des deux côtés : même crête à gauche et à droite.
                    vDSP_maxmgv(data[min(channel, channels - 1)], 1, &peak, frames)
                    meters.record(column: column, channel: channel, peak: peak)
                }
            }
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

        // Un pad disparu s'arrête. Un pad déplacé continue sur le mélangeur de sa nouvelle colonne.
        // Un pad dont les réglages changent garde le son en cours ; les nouveaux réglages valent au prochain appui.
        for (id, entry) in entries {
            guard let new = wanted[id] else {
                dropVoice(id)
                entries[id] = nil
                continue
            }
            if new.column != entry.column {
                entries[id]?.column = new.column
                if let voice = voices[id], let moved = entries[id] {
                    // Rebrancher un lecteur l'arrête : on le relance là où il en était (micro-coupure possible).
                    let state = voice.state
                    engine.disconnectNodeOutput(voice.gainNode)
                    engine.connect(voice.gainNode, to: columnMixers[new.column], format: voice.format)
                    resume(id, entry: moved, from: state, now: ProcessInfo.processInfo.systemUptime)
                }
            }
            if new.clip != entry.clip {
                var sameButGain = new.clip
                sameButGain.gainDB = entry.clip.gainDB
                if sameButGain == entry.clip {
                    // Seul le volume du pad a changé : rien à recharger, la voix en cours suit tout de suite.
                    entries[id]?.clip.gainDB = new.clip.gainDB
                    voices[id]?.gainNode.globalGain = Gain.engineDecibels(forPadGainDB: new.clip.gainDB)
                } else {
                    entries[id] = nil  // rechargé ci-dessous
                }
            }
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

    /// Règle en direct le volume d'un pad (dB), son en cours de lecture compris ; sans effet sur un pad inconnu.
    /// Retenu pour les déclenchements suivants. La valeur du spectacle (annulable) est envoyée au relâchement.
    public func setPadGain(_ pad: Pad.ID, gainDB: Double) {
        guard entries[pad] != nil else { return }
        entries[pad]?.clip.gainDB = gainDB
        voices[pad]?.gainNode.globalGain = Gain.engineDecibels(forPadGainDB: gainDB)
    }

    /// Déplace la tête de lecture : le son reprend à `elapsed` secondes de la partie jouée (borné à sa durée).
    /// En pause, le pad reste en pause à cette position ; arrêté, il démarre de là.
    public func seek(_ pad: Pad.ID, to elapsed: TimeInterval) {
        guard let entry = entries[pad] else { return }
        let latest = max(entry.timing.duration - AudioClip.minimumLength, 0)
        let target = min(max(elapsed.isFinite ? elapsed : 0, 0), latest)
        let wasPaused = voices[pad]?.state.isPausedForSeek ?? false
        startVoice(pad, entry: entry, offset: target)
        if wasPaused { togglePause(pad) }
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
            // Un fondu d'arrêt est en cours : petits blocs (64 trames) pour que le volume suive la courbe de près.
            let fading = voices.values.contains { $0.offlineFade != nil }
            let count = AVAudioFrameCount(min(remaining, fading ? 64 : Int(offline.maxFrames)))
            for voice in voices.values {
                if let fade = voice.offlineFade { voice.player.volume = fade.startVolume * StopFade.gain(elapsed: fade.elapsed) }
            }
            guard try engine.renderOffline(count, to: offline.buffer) == .success,
                let channels = offline.buffer.floatChannelData
            else { throw AudioEngineError.renderFailed }
            for i in 0..<Int(offline.buffer.frameLength) {
                result.append(channels[0][i])
                result.append(channels[1][i])
            }
            remaining -= Int(count)
            for voice in voices.values {
                guard var fade = voice.offlineFade else { continue }
                fade.elapsed += Double(count) / offline.format.sampleRate
                if fade.elapsed >= StopFade.duration {
                    voice.player.stop()
                    voice.player.volume = 1
                    voice.offlineFade = nil
                } else {
                    voice.offlineFade = fade
                }
            }
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
            let body = ClipRenderer.bake(raw, timing: timing.withoutFades, gainDB: 0)
            let intro = timing.fadeIn > 0 ? ClipRenderer.bake(raw, timing: timing.withoutFadeOut, gainDB: 0) : nil
            source = body.map { .buffered(intro: intro, body: $0) }
        } else {
            source = ClipRenderer.bake(raw, timing: timing, gainDB: 0).map { .buffered(intro: nil, body: $0) }
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
        engine.attach(voice.gainNode)
        engine.connect(voice.player, to: voice.gainNode, format: entry.format)
        engine.connect(voice.gainNode, to: columnMixers[entry.column], format: entry.format)
        voice.gainNode.globalGain = Gain.engineDecibels(forPadGainDB: entry.clip.gainDB)
        voices[pad] = voice
        return voice
    }

    private func dropVoice(_ pad: Pad.ID) {
        guard let voice = voices.removeValue(forKey: pad) else { return }
        let wasActive = voice.state.isActive
        voice.generation = -1
        voice.envelopeTask?.cancel()
        voice.offlineFade = nil
        voice.player.stop()
        engine.detach(voice.player)
        engine.detach(voice.gainNode)
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
        voice.offlineFade = nil  // un départ pendant un fondu d'arrêt : le fondu est abandonné, le volume est remis ci-dessous
        voice.player.stop()

        let now = ProcessInfo.processInfo.systemUptime
        voice.state = .playing(startedAt: now - offset)
        voice.player.volume = entry.isStreamed ? Float(entry.timing.envelope(at: offset)) : 1
        voice.gainNode.globalGain = Gain.engineDecibels(forPadGainDB: entry.clip.gainDB)
        schedule(entry, pad: pad, voice: voice, offset: offset)
        voice.player.play()
        if entry.isStreamed, entry.timing.fadeIn > 0 || entry.timing.fadeOut > 0 { runEnvelope(pad, timing: entry.timing, loops: entry.clip.loops, voice: voice) }
        emit(pad)
    }

    private func resumeVoice(_ pad: Pad.ID) {
        guard let voice = voices[pad], case .paused(let elapsed) = voice.state else { return }
        voice.player.play()
        voice.state = .playing(startedAt: ProcessInfo.processInfo.systemUptime - elapsed)
        emit(pad)
    }

    /// Arrête un son : l'état passe tout de suite à « arrêté » (interface, LED), mais le son descend à zéro en
    /// `StopFade.duration` avant que le lecteur ne soit coupé. Un son en pause ne sonne pas : arrêt net.
    private func stopVoice(_ pad: Pad.ID) {
        guard let voice = voices[pad], voice.state.isActive else { return }
        let wasSounding: Bool = if case .playing = voice.state { true } else { false }
        nextGeneration += 1
        voice.generation = nextGeneration  // invalide les callbacks de fin en attente
        voice.envelopeTask?.cancel()
        voice.state = .idle
        if wasSounding { beginFadeOut(pad, voice: voice) } else { voice.player.stop() }
        emit(pad)
    }

    private func beginFadeOut(_ pad: Pad.ID, voice: Voice) {
        let startVolume = voice.player.volume
        if offline != nil {
            // Pas d'horloge en rendu hors ligne : `renderOffline` fait avancer le fondu trame par trame.
            voice.offlineFade = (startVolume, 0)
            return
        }
        let generation = voice.generation
        let began = ProcessInfo.processInfo.systemUptime
        voice.envelopeTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, await self.stepFadeOut(pad, generation: generation, began: began, startVolume: startVolume)
                else { return }
                try? await Task.sleep(for: .milliseconds(4))
            }
        }
    }

    /// Une étape du fondu d'arrêt ; `false` quand il est fini (le lecteur est alors coupé) ou périmé (nouveau départ).
    private func stepFadeOut(_ pad: Pad.ID, generation: Int, began: TimeInterval, startVolume: Float) -> Bool {
        guard let voice = voices[pad], voice.generation == generation else { return false }
        let elapsed = ProcessInfo.processInfo.systemUptime - began
        guard elapsed < StopFade.duration else {
            voice.player.stop()
            voice.player.volume = 1  // remis pendant le silence : le mélangeur lisse les changements de volume, l'attaque du prochain départ resterait molle
            return false
        }
        voice.player.volume = startVolume * StopFade.gain(elapsed: elapsed)
        return true
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
    private func runEnvelope(_ pad: Pad.ID, timing: ClipTiming, loops: Bool, voice: Voice) {
        let generation = voice.generation
        voice.envelopeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                guard let self,
                    await self.updateEnvelope(pad, timing: timing, loops: loops, generation: generation)
                else { return }
            }
        }
    }

    private func updateEnvelope(_ pad: Pad.ID, timing: ClipTiming, loops: Bool, generation: Int) -> Bool {
        guard let voice = voices[pad], voice.generation == generation else { return false }
        guard case .playing(let startedAt) = voice.state else { return true }  // en pause : on attend
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        voice.player.volume = Float(timing.envelope(at: elapsed))
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
            voice.offlineFade = nil
            voice.player.stop()
            engine.detach(voice.player)
            engine.detach(voice.gainNode)
        }
        engine.stop()
        meters.reset()
        let format = offline?.format ?? engine.outputNode.inputFormat(forBus: 0)
        for mixer in columnMixers {
            engine.disconnectNodeOutput(mixer)
            engine.connect(mixer, to: engine.mainMixerNode, format: format)
        }
        Self.installMeters(on: columnMixers, meters: meters)  // le format a pu changer avec la sortie : la prise de mesure est reposée
        do { try startEngineIfNeeded() } catch {
            log.error("Redémarrage du moteur impossible : \(error.localizedDescription)")
            for item in snapshot { continuation.yield(PlaybackEvent(pad: item.pad, state: .idle, duration: 0)) }
            return
        }
        for item in snapshot {
            guard let entry = entries[item.pad] else { continue }
            resume(item.pad, entry: entry, from: item.paused ? .paused(elapsed: item.elapsed) : .playing(startedAt: now - item.elapsed), now: now)
        }
    }

    /// Relance une voix là où elle en était (lecture ou pause). Une boucle reprend dans son tour courant.
    private func resume(_ pad: Pad.ID, entry: Entry, from state: PlaybackState, now: TimeInterval) {
        let elapsed: TimeInterval
        switch state {
        case .idle: return
        case .playing(let startedAt): elapsed = now - startedAt
        case .paused(let pausedAt): elapsed = pausedAt
        }
        let offset = entry.clip.loops ? elapsed.truncatingRemainder(dividingBy: max(entry.timing.duration, 0.001)) : elapsed
        startVoice(pad, entry: entry, offset: max(offset, 0))
        if case .paused = state { togglePause(pad) }
    }
}

extension PlaybackState {
    fileprivate var isPausedForSeek: Bool {
        if case .paused = self { true } else { false }
    }
}
