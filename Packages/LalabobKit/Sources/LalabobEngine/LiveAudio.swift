import Foundation
import LalabobAudio

// L'app ne dépend que de LalabobEngine : elle y trouve les types audio dont l'interface a besoin.
public typealias PlaybackState = LalabobAudio.PlaybackState
public typealias PlaybackEvent = LalabobAudio.PlaybackEvent
public typealias AudioOutputDevice = LalabobAudio.AudioOutputDevice

extension ShowController {
    /// Contrôleur relié à la vraie sortie audio du Mac. `audioDirectory` : le dossier `Audio/` des sons.
    public static func live(audioDirectory: URL) -> ShowController {
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        return ShowController(audio: AVAudioEngineController(), audioDirectory: audioDirectory)
    }
}

import LalabobMIDI

extension ControllerSession {
    /// Session reliée au vrai MIDI du Mac. `nil` si CoreMIDI n'est pas disponible.
    public static func live(for controller: ShowController) -> ControllerSession? {
        guard let transport = try? CoreMIDISession() else { return nil }
        return ControllerSession(controller: controller, transport: transport)
    }
}
