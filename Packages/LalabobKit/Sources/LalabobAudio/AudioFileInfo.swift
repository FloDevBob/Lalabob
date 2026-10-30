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

    /// « WAV · 44,1 kHz · stéréo », pour l'inspecteur. `nil` si le fichier n'est pas un son lisible.
    public static func describe(_ url: URL) -> String? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.fileFormat
        let rate = (format.sampleRate / 1000).formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_FR")))
        let channels =
            switch format.channelCount {
            case 1: "mono"
            case 2: "stéréo"
            default: "\(format.channelCount) canaux"
            }
        return "\(url.pathExtension.uppercased()) · \(rate) kHz · \(channels)"
    }
}
