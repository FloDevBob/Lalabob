import AVFoundation
import Foundation
import LalabobAudio
import LalabobModel
import Testing

@testable import LalabobEngine

@MainActor
@Suite("Réglages audio dans l'inspecteur")
struct ClipEditingTests {
    static let a = GridPosition(column: 0, row: 0)

    private func makeController(locked: Bool = false) -> (ShowController, UndoManager) {
        var grid = PadGrid.empty(name: "G")
        grid[Self.a] = Pad(title: "Rire", tint: .vert, content: .audio(clip: AudioClip(fileName: "rire.wav")))
        let controller = ShowController(
            show: Show(name: "S", grids: [grid]), defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!,
            isLocked: locked)
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.undoManager = undo
        return (controller, undo)
    }

    private func clip(_ controller: ShowController) -> AudioClip? {
        if case .audio(let clip) = controller.pad(at: Self.a)?.content { clip } else { nil }
    }

    @Test func trimFadesLoopAndRetriggerAreEditableAndUndoable() {
        let (controller, undo) = makeController()
        controller.setTrim(at: Self.a, start: 1, end: 4, fileDuration: 10)
        controller.setFades(at: Self.a, in: 0.5, out: 2)
        controller.setLoops(at: Self.a, true)
        controller.setRetrigger(at: Self.a, .stop)
        let edited = clip(controller)
        #expect(edited?.trimStart == 1)
        #expect(edited?.trimEnd == 4)
        #expect(edited?.fadeIn == 0.5)
        #expect(edited?.fadeOut == 2)
        #expect(edited?.loops == true)
        #expect(edited?.retrigger == .stop)

        undo.undo()  // nouvel appui
        undo.undo()  // boucle
        #expect(clip(controller)?.loops == false)
        #expect(clip(controller)?.retrigger == .restart)
    }

    @Test func settingsAreRefusedWhenLocked() {
        let (controller, undo) = makeController(locked: true)
        controller.setLoops(at: Self.a, true)
        controller.setTrim(at: Self.a, start: 1, end: 2, fileDuration: 10)
        #expect(clip(controller)?.loops == false)
        #expect(clip(controller)?.trimStart == 0)
        #expect(!undo.canUndo)
    }

    @Test func settingsOnALightPadOrEmptyCellDoNothing() {
        let (controller, undo) = makeController()
        controller.setLoops(at: GridPosition(column: 3, row: 3), true)
        #expect(!undo.canUndo)
    }

    @Test func waveformIsComputedOnceThenReadFromTheCache() async throws {
        let audio = FileManager.default.temporaryDirectory.appending(path: "lalabob-wave-\(UUID().uuidString)")
        let cache = FileManager.default.temporaryDirectory.appending(path: "lalabob-wave-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        try TestAudio.write(named: "rire.wav", in: audio, seconds: 1, value: 0.5)
        let store = WaveformStore(cacheDirectory: cache)

        let first = try await store.waveform(for: audio.appending(path: "rire.wav"), buckets: 64)
        #expect(first.peaks.count == 64)
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).count == 1)

        // Fichier remplacé par un autre (taille différente) : recalcul.
        try TestAudio.write(named: "rire.wav", in: audio, seconds: 2, value: 0.25)
        let second = try await store.waveform(for: audio.appending(path: "rire.wav"), buckets: 64)
        #expect(abs(second.duration - 2) < 0.01)
        #expect(abs((second.peaks.first ?? 0) - 0.25) < 0.001)
    }
}

/// Écrit un WAV mono 8 kHz de valeur constante.
enum TestAudio {
    static func write(named name: String, in dir: URL, seconds: Double, value: Float) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * 8000)),
            let samples = buffer.floatChannelData
        else { return }
        buffer.frameLength = buffer.frameCapacity
        for i in 0..<Int(buffer.frameLength) { samples[0][i] = value }
        let url = dir.appending(path: name)
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
