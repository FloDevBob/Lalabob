import Foundation
import LalabobAudio
import LalabobModel

// L'app ne dépend que de LalabobEngine : elle y trouve les types audio dont l'interface a besoin.
public typealias PlaybackState = LalabobAudio.PlaybackState
public typealias PlaybackEvent = LalabobAudio.PlaybackEvent
public typealias AudioOutputDevice = LalabobAudio.AudioOutputDevice

extension ShowController {
    /// Spectacle relié à la vraie sortie audio du Mac (un moteur par fenêtre).
    /// `audioDirectory` : le dossier de travail des sons du document.
    public static func live(show: Show, audioDirectory: URL) -> ShowController {
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        return ShowController(show: show, audio: AVAudioEngineController(), audioDirectory: audioDirectory)
    }
}

import LalabobMIDI

extension ControllerSession {
    /// Session reliée au vrai MIDI du Mac. `nil` si CoreMIDI n'est pas disponible.
    public static func live() -> ControllerSession? {
        guard let transport = try? CoreMIDISession() else { return nil }
        return ControllerSession(transport: transport)
    }
}
