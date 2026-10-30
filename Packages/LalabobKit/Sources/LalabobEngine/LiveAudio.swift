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
