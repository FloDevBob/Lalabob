import AVFoundation
import Foundation

/// Informations sur un fichier son, lues sans le charger.
public enum AudioFileInfo {
    /// Durée en secondes, ou `nil` si le fichier n'est pas un son lisible.
    public static func duration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.processingFormat.sampleRate
        guard rate > 0 else { return nil }
        return Double(file.length) / rate
    }
}
