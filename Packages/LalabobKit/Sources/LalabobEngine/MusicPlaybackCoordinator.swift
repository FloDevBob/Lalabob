import AppKit
import Foundation
import LalabobAudio
import LalabobModel
import Observation

/// La lecture des pads Apple Music (spec « Grilles Apple Music », étape 3). Music n'a qu'un lecteur : **un morceau à la fois**,
/// partagé par toutes les fenêtres.
///
/// - Appui sur un pad : lance son morceau (`play … with once` : silence à la fin, Music n'enchaîne pas la suite).
/// - Ré-appui sur le pad qui joue : pause ; encore : reprise.
/// - Un autre pad pendant qu'un morceau joue : **fondu enchaîné** (le volume de Music descend, changement de morceau, il remonte).
/// - Stop de colonne : fondu de sortie ; « Tout arrêter » (Échap) : fondu court.
///
/// Le volume général de Music appartient au 9e fader de l'APC ; pendant un fondu, le fader change la cible au lieu d'écrire
/// lui-même (`faderMoved`). L'état publié chez le spectacle (`ShowController.applyMusicPlayback`) a la forme d'un son de Lalabob :
/// lueur, progression, LED et panneau du bas le suivent sans rien de plus.
@MainActor
@Observable
public final class MusicPlaybackCoordinator {
    @ObservationIgnored private let player: any MusicPlayerControlling

    /// Durée totale du fondu enchaîné (moitié pour descendre, moitié pour remonter).
    public var crossfadeDuration: TimeInterval = 1
    /// Fondu de sortie d'un stop de colonne.
    public var stopFadeDuration: TimeInterval = 1
    /// Fondu de sortie de « Tout arrêter » (Échap).
    public var stopAllFadeDuration: TimeInterval = 0.3
    /// Fréquence de lecture de l'état de Music (position, fin du morceau).
    public var pollInterval: Duration = .milliseconds(250)
    /// Intervalle entre deux pas de volume pendant un fondu.
    public var rampStep: TimeInterval = 0.05

    /// **Pont audio** (ADR 0011) : le son de Music est capté (Music devient muet) et joué par Lalabob dans la colonne du morceau
    /// (fader, filtre, vumètre, sortie de Lalabob ; fondus lissés). Désactivé par défaut ; mémorisé sur ce Mac.
    public private(set) var isBridgeEnabled: Bool
    /// La capture tourne : le son du morceau passe par Lalabob.
    public private(set) var isBridging = false
    /// Pourquoi le pont n'a pas pu servir (affiché dans le panneau) ; `nil` si tout va bien.
    public private(set) var bridgeProblem: String?
    /// Le tampon entre la capture et le moteur.
    @ObservationIgnored public let ring = AudioRingBuffer(capacity: 32_768, latencyFrames: 3_072)  // ≈ 65 ms d'avance
    @ObservationIgnored private let capture: any MusicAudioCapturing
    @ObservationIgnored private let musicPID: @MainActor () -> pid_t?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var bridgeRate: Double = 48_000
    @ObservationIgnored private var bridgeStartedAt: TimeInterval = 0
    /// Ce que la capture a trouvé (fréquences, entrées sautées) : affiché pour le diagnostic.
    public private(set) var bridgeInfo: ProcessAudioBridge.Info?
    /// La sortie du spectacle qui va jouer (avant que `owner` soit posé, au premier appui).
    @ObservationIgnored private var pendingOwnerOutput: String?
    /// Coupures et sauts du tampon depuis le démarrage du pont : chacun s'entend (diagnostic).
    public var bridgeGlitches: (underruns: Int, skips: Int) { (ring.underruns, ring.skips) }
    static let bridgeDefaultsKey = "musicBridgeEnabled"
    /// Délais de sécurité du pont : grâce au démarrage, capture muette (plus rien d'écrit), son resté silencieux.
    public var bridgeGrace: TimeInterval = 2
    public var bridgeStaleLimit: TimeInterval = 1.5
    public var bridgeSilenceLimit: TimeInterval = 4

    public private(set) var currentPad: Pad.ID?
    public private(set) var state: MusicPlayerState = .stopped
    public private(set) var isFading = false

    @ObservationIgnored private var currentTrackID: String?
    /// Instant (uptime) du dernier départ, et lectures de suite qui disent le morceau fini (voir `poll`).
    @ObservationIgnored private var startedAt: TimeInterval = 0
    @ObservationIgnored private var endReadings = 0
    /// Délai après un départ pendant lequel une fin annoncée par Music n'est pas crue.
    public var startGrace: TimeInterval = 1.5
    @ObservationIgnored private var duration: TimeInterval = 0
    @ObservationIgnored private var position: TimeInterval = 0
    /// Volume demandé par le 9e fader (0 à 100), `nil` tant qu'il n'a pas bougé.
    @ObservationIgnored private var faderTarget: Int?
    /// Dernier volume « plein » connu (pour ne jamais rester à 0 après un fondu interrompu).
    @ObservationIgnored private var lastFullVolume = 100
    @ObservationIgnored private weak var owner: ShowController?
    @ObservationIgnored private var transition: Task<Void, Never>?
    @ObservationIgnored private var polling: Task<Void, Never>?
    /// Chaque geste invalide les gestes précédents encore en cours (un appui rapide après un autre gagne).
    @ObservationIgnored private var generation = 0

    public init(
        player: any MusicPlayerControlling, capture: any MusicAudioCapturing = ProcessAudioBridge(), defaults: UserDefaults = .standard,
        musicPID: @escaping @MainActor () -> pid_t? = {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first?.processIdentifier
        }
    ) {
        self.player = player
        self.capture = capture
        self.defaults = defaults
        self.musicPID = musicPID
        self.isBridgeEnabled = defaults.bool(forKey: Self.bridgeDefaultsKey)
    }

    // MARK: Pont audio

    /// Active ou coupe le pont audio. Activé pendant un morceau : le son bascule tout de suite dans sa colonne.
    public func setBridgeEnabled(_ enabled: Bool) {
        isBridgeEnabled = enabled
        defaults.set(enabled, forKey: Self.bridgeDefaultsKey)
        bridgeProblem = nil
        Task {
            if enabled {
                if await startBridge(), let pad = currentPad {
                    ring.setGain(1, overFrames: 0)
                    owner?.attachMusicBridge(ring, sampleRate: bridgeRate, pad: pad)
                }
            } else {
                await stopBridge()
            }
        }
    }

    /// Démarre la capture si l'option est active ; `true` si le son passe par Lalabob. Refusée : Music joue directement.
    private func startBridge() async -> Bool {
        guard isBridgeEnabled else { return false }
        if isBridging { return true }
        guard let pid = musicPID() else { return false }
        do {
            let info = try await capture.start(pid: pid, outputUID: pendingOwnerOutput ?? owner?.selectedOutputUID, into: ring)
            bridgeRate = info.sampleRate
            bridgeInfo = info
            isBridging = true
            bridgeStartedAt = ProcessInfo.processInfo.systemUptime
            bridgeProblem = nil
            return true
        } catch {
            bridgeProblem = "Le son de Music ne peut pas passer par Lalabob : autorisez l'enregistrement audio (Réglages Système › Confidentialité et sécurité). Music joue directement."
            return false
        }
    }

    /// Défait la capture : Music redevient audible tout seul (sa sortie n'est plus coupée).
    private func stopBridge(reason: String? = nil) async {
        guard isBridging else { return }
        isBridging = false
        await capture.stop()
        owner?.detachMusicBridge()
        if let reason { bridgeProblem = reason }
    }

    /// La sortie du spectacle qui joue a changé : la capture redémarre sur l'horloge de la nouvelle sortie.
    public func outputChanged(to uid: String?, owner changed: ShowController) {
        guard isBridging, owner === changed else { return }
        pendingOwnerOutput = uid
        Task {
            isBridging = false
            await capture.stop()
            ring.setGain(1, overFrames: 0)
            if await startBridge(), let pad = currentPad { owner?.attachMusicBridge(ring, sampleRate: bridgeRate, pad: pad) }
        }
    }

    /// Fondu fait dans Lalabob (pont actif) : le gain du tampon glisse échantillon par échantillon, sans à-coup.
    private func bridgeFade(to gain: Float, over duration: TimeInterval) async {
        ring.setGain(gain, overFrames: Int(max(0, duration) * bridgeRate))
        if duration > 0 { try? await Task.sleep(for: .seconds(duration)) }
    }

    // MARK: Gestes

    /// Appui sur un pad Apple Music (contrôleur, double-clic, bouton du pad) — décision du 27/11/2026 : un morceau qui joue
    /// **s'arrête** (fondu de 1 s) ; en pause, il **reprend** ; arrêté, il **repart du début**.
    public func press(_ pad: Pad, owner: ShowController) {
        guard let track = pad.music else { return }
        if pad.id == currentPad, self.owner === owner {
            switch state {
            case .playing: return stopCurrent(fade: stopFadeDuration)
            case .paused: return resume()
            case .stopped: break
            }
        }
        start(padID: pad.id, track: track, owner: owner)
    }

    /// Pause / reprise (barre du bas, Espace) ; un morceau arrêté démarre.
    public func togglePause(_ pad: Pad, owner: ShowController) {
        guard let track = pad.music else { return }
        if pad.id == currentPad, self.owner === owner {
            switch state {
            case .playing: return pause()
            case .paused: return resume()
            case .stopped: break
            }
        }
        start(padID: pad.id, track: track, owner: owner)
    }

    /// Arrête le morceau de ce pad s'il est le morceau en cours (fondu de sortie).
    public func stop(padID: Pad.ID, fade: TimeInterval? = nil) {
        guard padID == currentPad else { return }
        stopCurrent(fade: fade ?? stopFadeDuration)
    }

    /// Arrête le morceau en cours, quel qu'il soit (« Tout arrêter »).
    public func stopAll() {
        guard currentPad != nil else { return }
        stopCurrent(fade: stopAllFadeDuration)
    }

    /// Le 9e fader a bougé (0 à 100) : c'est la cible des fondus. Pendant un fondu, l'appelant ne doit pas écrire le volume
    /// lui-même (`isFading`) : le fondu rejoint la nouvelle cible.
    public func faderMoved(percent: Int) {
        faderTarget = max(0, min(percent, 100))
        if percent > 0 { lastFullVolume = percent }
    }

    /// Déplace la lecture dans le morceau en cours (barre de position du panneau du bas).
    public func seek(padID: Pad.ID, to seconds: TimeInterval) {
        guard padID == currentPad, seconds.isFinite else { return }
        let target = max(0, min(seconds, duration > 0 ? duration : seconds))
        Task {
            try? await player.seek(to: target)
            position = target
            publish()
        }
    }

    // MARK: Transitions

    private func start(padID: Pad.ID, track: MusicTrackRef, owner: ShowController) {
        generation += 1
        let gen = generation
        transition?.cancel()
        let previousPad = currentPad
        let previousOwner = self.owner
        let wasPlaying = state == .playing
        pendingOwnerOutput = owner.selectedOutputUID
        transition = Task {
            guard await player.isRunning() else {
                owner.showMusicNotice("Apple Music est fermé : ouvrez Music sur ce Mac pour jouer ce morceau.")
                return
            }
            let full = await fullVolume()
            let bridged = await startBridge()
            if wasPlaying {
                if bridged { await bridgeFade(to: 0, over: crossfadeDuration / 2) } else { await ramp(to: { 0 }, over: crossfadeDuration / 2, gen) }
            }
            guard gen == generation else { return }
            if bridged, !wasPlaying { ring.setGain(1, overFrames: 0) }
            // L'ancien pad s'éteint à l'écran et sur le contrôleur.
            if let previousPad { previousOwner?.applyMusicPlayback(PlaybackEvent(pad: previousPad, state: .idle, duration: 0)) }
            clear(publishing: false)
            do {
                if !wasPlaying { try await player.setVolume(full) }
                guard try await player.play(trackID: track.persistentID) else {
                    try? await player.setVolume(full)
                    owner.showMusicNotice("« \(track.title) » n'est plus dans la bibliothèque de Music : remplacez le morceau.")
                    return
                }
            } catch {
                try? await player.setVolume(full)
                owner.showMusicNotice(Self.message(for: error))
                return
            }
            guard gen == generation else { return }
            currentPad = padID
            currentTrackID = track.persistentID
            startedAt = ProcessInfo.processInfo.systemUptime
            endReadings = 0
            duration = track.duration
            position = 0
            state = .playing
            self.owner = owner
            if bridged { owner.attachMusicBridge(ring, sampleRate: bridgeRate, pad: padID) }  // le son va dans la colonne de ce pad
            publish()
            startPolling()
            if wasPlaying {
                if bridged {
                    await bridgeFade(to: 1, over: crossfadeDuration / 2)
                } else {
                    await ramp(to: { [weak self] in self?.faderTarget ?? full }, over: crossfadeDuration / 2, gen)
                }
            }
        }
    }

    private func pause() {
        generation += 1
        transition?.cancel()
        transition = Task {
            do { try await player.pause() } catch { return }
            state = .paused
            publish()
        }
    }

    private func resume() {
        generation += 1
        transition?.cancel()
        transition = Task {
            do { try await player.resume() } catch { return }
            state = .playing
            publish()
        }
    }

    private func stopCurrent(fade: TimeInterval) {
        generation += 1
        let gen = generation
        transition?.cancel()
        let wasPlaying = state == .playing
        transition = Task {
            let full = await fullVolume()
            if wasPlaying, fade > 0 {
                if isBridging { await bridgeFade(to: 0, over: fade) } else { await ramp(to: { 0 }, over: fade, gen) }
            }
            guard gen == generation else { return }
            try? await player.stop()
            try? await player.setVolume(faderTarget ?? full)  // Music garde son volume pour la suite
            clear(publishing: true)
        }
    }

    /// Le volume « plein » d'où partent et où reviennent les fondus : celui du 9e fader, sinon celui de Music (jamais 0).
    private func fullVolume() async -> Int {
        if let faderTarget { return faderTarget }
        if let current = try? await player.volume(), current > 0, !isFading { lastFullVolume = current }
        return lastFullVolume
    }

    /// Fait glisser le volume de Music vers `target` (relu à chaque pas : le 9e fader peut la changer) en `duration` secondes.
    private func ramp(to target: @escaping () -> Int, over duration: TimeInterval, _ gen: Int) async {
        let start = (try? await player.volume()) ?? target()
        let steps = max(1, Int((duration / rampStep).rounded()))
        isFading = true
        defer { if gen == generation { isFading = false } }
        for step in 1...steps {
            guard gen == generation, !Task.isCancelled else { return }
            let fraction = Double(step) / Double(steps)
            let value = Int((Double(start) + Double(target() - start) * fraction).rounded())
            try? await player.setVolume(value)
            try? await Task.sleep(for: .seconds(rampStep))
        }
        isFading = false
    }

    // MARK: Suivi de Music

    private func startPolling() {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                await self.poll()
                if self.currentPad == nil { return }
            }
        }
    }

    private func poll() async {
        guard currentPad != nil, !isFading else { return }
        let gen = generation
        let expected = currentTrackID
        guard let snapshot = try? await player.snapshot() else { return }
        // Bug du 27/11/2026 : une réponse partie avant un autre geste (changement de morceau, pause…) et revenue après est
        // périmée ; la prendre au mot éteignait le nouveau pad alors que Music le jouait. On l'ignore.
        guard gen == generation, expected == currentTrackID, currentPad != nil else { return }
        // Fin du morceau, ou Music joue autre chose (quelqu'un a changé de morceau dans Music) : le pad s'éteint. Mais juste après
        // un départ, Music annonce encore un instant l'ancien morceau ou « arrêté » : on attend `startGrace`, et deux lectures
        // de suite qui le disent.
        if snapshot.state == .stopped || snapshot.trackID != currentTrackID {
            guard ProcessInfo.processInfo.systemUptime - startedAt > startGrace else { return }
            endReadings += 1
            if endReadings >= 2, snapshot.state == .stopped || !snapshot.trackID.isEmpty { clear(publishing: true) }
            return
        }
        endReadings = 0
        await checkBridgeHealth(position: snapshot.position, playing: snapshot.state == .playing)
        let drift = abs(snapshot.position - expectedPosition)
        let changed = snapshot.state != state
        position = snapshot.position
        state = snapshot.state
        if changed || drift > 0.5 { publish() }
    }

    /// Sécurité en scène (ADR 0011) : si la capture ne fournit plus rien, ou seulement du silence (morceau protégé ?), le pont est
    /// défait et Music redevient audible.
    private func checkBridgeHealth(position: TimeInterval, playing: Bool) async {
        guard isBridging, playing, ProcessInfo.processInfo.systemUptime - bridgeStartedAt > bridgeGrace else { return }
        if ring.secondsSinceLastWrite > bridgeStaleLimit {
            await stopBridge(reason: "La capture du son de Music s'est arrêtée : Music joue directement.")
        } else if position > bridgeSilenceLimit, ring.secondsSinceLastSound > bridgeSilenceLimit {
            await stopBridge(reason: "Le son de Music arrive muet dans Lalabob (morceau protégé ?) : Music joue directement. Option désactivée.")
            isBridgeEnabled = false
            defaults.set(false, forKey: Self.bridgeDefaultsKey)
        }
    }

    /// La position que l'écran affiche en ce moment (d'après le dernier état publié).
    private var expectedPosition: TimeInterval {
        guard let pad = currentPad, case .playing(let startedAt)? = owner?.playback[pad]?.state else { return position }
        return ProcessInfo.processInfo.systemUptime - startedAt
    }

    private func publish() {
        guard let pad = currentPad else { return }
        let playbackState: PlaybackState =
            switch state {
            case .playing: .playing(startedAt: ProcessInfo.processInfo.systemUptime - position)
            case .paused: .paused(elapsed: position)
            case .stopped: .idle
            }
        owner?.applyMusicPlayback(PlaybackEvent(pad: pad, state: playbackState, duration: duration))
    }

    private func clear(publishing: Bool) {
        if publishing, let pad = currentPad { owner?.applyMusicPlayback(PlaybackEvent(pad: pad, state: .idle, duration: 0)) }
        polling?.cancel()
        polling = nil
        currentPad = nil
        currentTrackID = nil
        state = .stopped
        position = 0
    }

    private static func message(for error: any Error) -> String {
        switch error as? MediaVolumeError {
        case .notAuthorized: "macOS refuse à Lalabob l'accès à Music : Réglages Système › Confidentialité et sécurité › Automatisation."
        case .failed(let message): "Music a répondu par une erreur : \(message)"
        case nil: "Music a répondu par une erreur : \(error.localizedDescription)"
        }
    }
}
