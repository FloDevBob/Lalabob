import Foundation
import LalabobAudio
import Testing

@testable import LalabobEngine

@MainActor
final class FakePreviewer: AudioPreviewing {
    var onFinish: (() -> Void)?
    private(set) var playedURLs: [URL] = []
    private(set) var devices: [String?] = []
    private(set) var stopCount = 0
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 4
    var failure: Error?

    func play(url: URL, deviceUID: String?) throws {
        if let failure { throw failure }
        playedURLs.append(url)
        devices.append(deviceUID)
        isPlaying = true
    }
    func stop() {
        stopCount += 1
        isPlaying = false
    }
    func finishNaturally() {
        isPlaying = false
        onFinish?()
    }
}

@MainActor
@Suite("Pré-écoute")
struct PreviewTests {
    private let rire = AudioLibraryItem(url: URL(filePath: "/tmp/rire.wav"), name: "rire.wav", duration: 4)
    private let porte = AudioLibraryItem(url: URL(filePath: "/tmp/porte.wav"), name: "porte.wav", duration: 2)

    @Test func toggleStartsThenStops() {
        let fake = FakePreviewer()
        let preview = PreviewController(previewer: fake)
        preview.toggle(rire, deviceUID: "carte-1", isLocked: false)
        #expect(preview.playingItem == rire.id)
        #expect(fake.playedURLs == [rire.url])
        #expect(fake.devices == ["carte-1"])  // même sortie que le spectacle

        preview.toggle(rire, deviceUID: "carte-1", isLocked: false)
        #expect(preview.playingItem == nil)
        #expect(!fake.isPlaying)
    }

    @Test func anotherSoundReplacesTheCurrentOne() {
        let fake = FakePreviewer()
        let preview = PreviewController(previewer: fake)
        preview.toggle(rire, deviceUID: nil, isLocked: false)
        preview.toggle(porte, deviceUID: nil, isLocked: false)
        #expect(preview.playingItem == porte.id)
        #expect(fake.playedURLs == [rire.url, porte.url])
    }

    @Test func lockedShowRefusesAndStops() {
        let fake = FakePreviewer()
        let preview = PreviewController(previewer: fake)
        preview.toggle(rire, deviceUID: nil, isLocked: false)
        preview.toggle(porte, deviceUID: nil, isLocked: true)
        #expect(preview.playingItem == nil)
        #expect(!fake.isPlaying)
        #expect(fake.playedURLs == [rire.url])  // porte n'a jamais démarré
    }

    @Test func stopIsHarmlessWhenNothingPlays() {
        let preview = PreviewController(previewer: FakePreviewer())
        preview.stop()
        #expect(preview.playingItem == nil)
    }

    @Test func naturalEndResetsTheState() {
        let fake = FakePreviewer()
        let preview = PreviewController(previewer: fake)
        preview.toggle(rire, deviceUID: nil, isLocked: false)
        fake.finishNaturally()
        #expect(preview.playingItem == nil)
        #expect(preview.progress == 0)
    }

    @Test func failureIsReportedAndLeavesNothingPlaying() {
        struct Boom: Error {}
        let fake = FakePreviewer()
        fake.failure = Boom()
        let preview = PreviewController(previewer: fake)
        preview.toggle(rire, deviceUID: nil, isLocked: false)
        #expect(preview.playingItem == nil)
        #expect(preview.error?.contains("rire.wav") == true)
    }

    @Test func progressFollowsThePlayer() {
        let fake = FakePreviewer()
        let preview = PreviewController(previewer: fake)
        preview.toggle(rire, deviceUID: nil, isLocked: false)
        fake.currentTime = 1
        preview.refreshProgress()
        #expect(abs(preview.progress - 0.25) < 1e-9)
        fake.currentTime = 99  // jamais au-delà de 1
        preview.refreshProgress()
        #expect(preview.progress == 1)
    }
}
