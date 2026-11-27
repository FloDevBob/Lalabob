import Foundation
import LalabobModel

/// État du lecteur de l'app Music.
public enum MusicPlayerState: Equatable, Sendable {
    case stopped, playing, paused
}

/// Ce que Music joue en ce moment.
public struct MusicPlayerSnapshot: Equatable, Sendable {
    public var state: MusicPlayerState
    /// `persistent ID` du morceau en cours (vide si aucun).
    public var trackID: String
    /// Position dans le morceau, en secondes.
    public var position: TimeInterval

    public init(state: MusicPlayerState, trackID: String = "", position: TimeInterval = 0) {
        self.state = state
        self.trackID = trackID
        self.position = position
    }
}

/// Piloter le lecteur de Music (une implémentation par AppleScript, une fausse pour les tests). Aucune méthode ne lance Music.
public protocol MusicPlayerControlling: Sendable {
    func isRunning() async -> Bool
    /// Joue ce morceau **une fois** puis s'arrête (Music n'enchaîne pas la suite) ; `false` s'il n'est pas dans la bibliothèque.
    func play(trackID: String) async throws -> Bool
    func pause() async throws
    func resume() async throws
    func stop() async throws
    func seek(to seconds: TimeInterval) async throws
    func snapshot() async throws -> MusicPlayerSnapshot
    func volume() async throws -> Int?
    func setVolume(_ percent: Int) async throws
}

/// Le lecteur réel : AppleScript vers l'app Music, sur la file des scripts (jamais sur le fil principal).
public actor AppleMusicPlayer: MusicPlayerControlling {
    public init() {}

    public func isRunning() async -> Bool { MusicScripting.isRunning }

    public func play(trackID: String) async throws -> Bool {
        guard MusicScripting.isRunning, MusicTrackRef.isValidPersistentID(trackID) else { return false }
        // `with once` : le morceau seul, puis silence (relevé dans com.apple.Music.sdef : paramètre `once` de `play`).
        let script = """
            set lbTracks to (every track of library playlist 1 whose persistent ID is "\(trackID)")
            if lbTracks is {} then return false
            play (item 1 of lbTracks) with once
            return true
            """
        return try await MusicScripting.run(script) { $0.booleanValue }
    }

    public func pause() async throws { try await simple("pause") }
    public func resume() async throws { try await simple("play") }
    public func stop() async throws { try await simple("stop") }

    public func seek(to seconds: TimeInterval) async throws {
        guard seconds.isFinite else { return }
        try await simple("set player position to \(max(0, seconds))")
    }

    public func snapshot() async throws -> MusicPlayerSnapshot {
        guard MusicScripting.isRunning else { return MusicPlayerSnapshot(state: .stopped) }
        let script = """
            set lbState to player state
            set lbID to ""
            set lbPosition to 0
            try
                set lbID to persistent ID of current track
                set lbPosition to player position
            end try
            return {lbState, lbID, lbPosition}
            """
        return try await MusicScripting.run(script) { result in
            let items = result.listItems
            guard items.count == 3 else { return MusicPlayerSnapshot(state: .stopped) }
            let state: MusicPlayerState =
                switch items[0].enumCodeValue {
                case OSType(0x6B50_5350), OSType(0x6B50_5346), OSType(0x6B50_5352): .playing  // 'kPSP', 'kPSF', 'kPSR'
                case OSType(0x6B50_5370): .paused  // 'kPSp'
                default: .stopped  // 'kPSS'
                }
            let position = items[2].doubleValue
            return MusicPlayerSnapshot(state: state, trackID: items[1].text, position: position.isFinite ? max(0, position) : 0)
        }
    }

    public func volume() async throws -> Int? {
        guard MusicScripting.isRunning else { return nil }
        return try await MusicScripting.run("get sound volume") { Int($0.int32Value) }
    }

    public func setVolume(_ percent: Int) async throws {
        try await simple("set sound volume to \(max(0, min(percent, 100)))")
    }

    private func simple(_ command: String) async throws {
        guard MusicScripting.isRunning else { return }
        _ = try await MusicScripting.run(command) { _ in 0 }
    }
}
