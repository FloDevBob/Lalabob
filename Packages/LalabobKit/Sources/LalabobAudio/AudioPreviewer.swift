import AVFoundation
import Foundation

/// Lecteur de pré-écoute : joue un fichier à part du moteur du spectacle (pas de fader, pas de pad).
@MainActor
public protocol AudioPreviewing: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    /// Appelé quand le son se termine tout seul (pas après `stop()`).
    var onFinish: (() -> Void)? { get set }

    /// Joue `url` sur la sortie `deviceUID` (`nil` = sortie par défaut).
    func play(url: URL, deviceUID: String?) throws
    func stop()
}

/// Pré-écoute réelle, fondée sur `AVAudioPlayer`, qui accepte un périphérique de sortie précis.
@MainActor
public final class AVAudioPreviewer: NSObject, AudioPreviewing, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    public var onFinish: (() -> Void)?

    public var isPlaying: Bool { player?.isPlaying ?? false }
    public var currentTime: TimeInterval { player?.currentTime ?? 0 }
    public var duration: TimeInterval { player?.duration ?? 0 }

    public override init() {
        super.init()
    }

    public func play(url: URL, deviceUID: String?) throws {
        stop()
        let player = try AVAudioPlayer(contentsOf: url)
        if let deviceUID, AudioOutputDevices.deviceID(forUID: deviceUID) != nil { player.currentDevice = deviceUID }
        player.delegate = self
        guard player.play() else { throw CocoaError(.fileReadUnknown) }
        self.player = player
    }

    public func stop() {
        player?.delegate = nil  // un arrêt volontaire n'est pas une fin naturelle
        player?.stop()
        player = nil
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            guard let current = self.player, ObjectIdentifier(current) == finished else { return }
            self.player = nil
            self.onFinish?()
        }
    }
}
