import Foundation
import Testing

@testable import LalabobImport

@Suite("Élagage et volume d'un clip Ableton")
struct AbletonTrimTests {
    /// Un clip dans une piste ; `frames` à 44,1 kHz.
    private func parse(warped: Bool, loopStart: Double, loopEnd: Double, volume: Double = 1, frames: Int = 441_000, warpMarkers: String = "") throws -> AbletonClip {
        let xml = """
            <Ableton><LiveSet><Tracks><AudioTrack><DeviceChain><MainSequencer><ClipSlotList>
            <ClipSlot><ClipSlot><Value><AudioClip>
              <Name Value="c"/>
              <Loop><LoopStart Value="\(loopStart)"/><LoopEnd Value="\(loopEnd)"/><LoopOn Value="false"/></Loop>
              <IsWarped Value="\(warped)"/>
              <SampleVolume Value="\(volume)"/>
              <WarpMarkers>\(warpMarkers)</WarpMarkers>
              <SampleRef><FileRef><Path Value="/x/c.wav"/></FileRef>
                <DefaultDuration Value="\(frames)"/><DefaultSampleRate Value="44100"/></SampleRef>
            </AudioClip></Value></ClipSlot></ClipSlot>
            </ClipSlotList></MainSequencer></DeviceChain></AudioTrack></Tracks></LiveSet></Ableton>
            """
        let set = try AbletonLiveSetReader.parse(xml: Data(xml.utf8))
        return try #require(set.audioTracks.first?.clips[0])
    }

    private let markers = #"<WarpMarker Id="0" SecTime="0" BeatTime="0"/><WarpMarker Id="1" SecTime="2" BeatTime="4"/>"#

    @Test("Clip non warpé : marqueurs en secondes")
    func unwarped() throws {
        let clip = try parse(warped: false, loopStart: 1, loopEnd: 3)
        #expect(clip.trimStart == 1)
        #expect(clip.trimEnd == 3)
    }

    @Test("Fin du fichier : pas de fin d'élagage")
    func endOfFile() throws {
        let clip = try parse(warped: false, loopStart: 0, loopEnd: 10)  // 441 000 images = 10 s
        #expect(clip.trimStart == 0)
        #expect(clip.trimEnd == nil)
    }

    @Test("Clip warpé : battements convertis par les marqueurs de warp, au-delà du dernier marqueur aussi")
    func warped() throws {
        // 2 battements par seconde : 2 battements = 1 s ; 12 battements = 6 s (extrapolé) ; 20 battements = 10 s = fin du fichier.
        let inside = try parse(warped: true, loopStart: 2, loopEnd: 12, warpMarkers: markers)
        #expect(abs(inside.trimStart - 1) < 1e-9)
        let end = try #require(inside.trimEnd)
        #expect(abs(end - 6) < 1e-9)
        #expect(try parse(warped: true, loopStart: 0, loopEnd: 20, warpMarkers: markers).trimEnd == nil)
    }

    @Test("Clip warpé sans marqueurs exploitables : tout le fichier, jamais une valeur inventée")
    func warpedWithoutMarkers() throws {
        let clip = try parse(warped: true, loopStart: 2, loopEnd: 12)
        #expect(clip.trimStart == 0)
        #expect(clip.trimEnd == nil)
    }

    @Test("Marqueurs absurdes : fin avant le début, ou durée du fichier inconnue")
    func absurdMarkers() throws {
        let reversed = try parse(warped: false, loopStart: 5, loopEnd: 2)
        #expect(reversed.trimEnd == nil)
        let unknownDuration = try parse(warped: false, loopStart: 1, loopEnd: 3, frames: 0)
        #expect(unknownDuration.trimStart == 0)
        #expect(unknownDuration.trimEnd == nil)
    }

    @Test("Volume : gain linéaire → décibels, borné, au dixième")
    func gain() throws {
        #expect(try parse(warped: false, loopStart: 0, loopEnd: 10, volume: 1).gainDB == 0)
        #expect(try parse(warped: false, loopStart: 0, loopEnd: 10, volume: 0.5).gainDB == -6)
        #expect(try parse(warped: false, loopStart: 0, loopEnd: 10, volume: 1.792).gainDB == 5.1)
        #expect(try parse(warped: false, loopStart: 0, loopEnd: 10, volume: 0).gainDB == 0)  // valeur absurde : neutre
        #expect(try parse(warped: false, loopStart: 0, loopEnd: 10, volume: 100).gainDB == 12)  // plafonné à la plage de l'inspecteur
    }
}
