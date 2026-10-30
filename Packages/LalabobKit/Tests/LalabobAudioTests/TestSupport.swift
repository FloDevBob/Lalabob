import AVFoundation
import Foundation

/// Écrit un fichier WAV stéréo 44,1 kHz dont chaque échantillon vaut `value(t)` (t en secondes).
func writeTestFile(
    named name: String,
    in directory: URL,
    duration: TimeInterval,
    sampleRate: Double = 44100,
    channels: AVAudioChannelCount = 2,
    value: (TimeInterval) -> Float
) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
    let frames = AVAudioFrameCount(duration * sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    for channel in 0..<Int(channels) {
        let data = buffer.floatChannelData![channel]
        for i in 0..<Int(frames) { data[i] = value(Double(i) / sampleRate) }
    }
    let file = try AVAudioFile(
        forWriting: directory.appendingPathComponent(name),
        settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
        ]
    )
    try file.write(from: buffer)
}

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lalabob-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Attend qu'une condition devienne vraie (les callbacks audio arrivent de façon asynchrone).
func waitUntil(timeout: TimeInterval = 2, _ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}
