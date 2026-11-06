import Foundation
import Testing

@testable import LalabobImport
@testable import LalabobModel

/// Les fichiers ci-dessous sont écrits à la main d'après la structure documentée par la communauté (voir ADR 0007) :
/// ils ne remplacent pas un vrai Live Set de Live 12. Quand un `.als` réel est disponible, l'ajouter en fixture.
enum LiveSetFixture {
    /// Deux pistes audio (« Rires » avec 2 clips, une piste sans nom utilisateur avec 1 clip en boucle), une piste MIDI,
    /// 3 scènes, plus un `FreezeSequencer` qui ne doit pas être lu.
    static let twoTracks = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton MajorVersion="5" MinorVersion="12.0_12049" Creator="Ableton Live 12.1.5 Suite" Revision="">
          <LiveSet>
            <Tracks>
              <AudioTrack Id="1">
                <Name><EffectiveName Value="1-Audio"/><UserName Value="Rires"/></Name>
                <DeviceChain>
                  <MainSequencer>
                    <ClipSlotList>
                      <ClipSlot Id="0"><ClipSlot><Value>
                        <AudioClip Id="0" Time="0">
                          <Name Value="Petit rire"/>
                          <Loop><LoopStart Value="0"/><LoopEnd Value="4"/><LoopOn Value="false"/></Loop>
                          <SampleRef><FileRef>
                            <RelativePathType Value="3"/>
                            <RelativePath Value="Samples/Imported/rire.wav"/>
                            <Path Value="/Users/x/Projet/Samples/Imported/rire.wav"/>
                          </FileRef></SampleRef>
                        </AudioClip>
                      </Value></ClipSlot></ClipSlot>
                      <ClipSlot Id="1"><ClipSlot><Value/></ClipSlot></ClipSlot>
                      <ClipSlot Id="2"><ClipSlot><Value>
                        <AudioClip Id="1" Time="0">
                          <Name Value=""/>
                          <SampleRef><FileRef><Path Value="/Users/x/Sons/applaudissements.mp3"/></FileRef></SampleRef>
                        </AudioClip>
                      </Value></ClipSlot></ClipSlot>
                    </ClipSlotList>
                  </MainSequencer>
                  <FreezeSequencer>
                    <ClipSlotList>
                      <ClipSlot Id="0"><ClipSlot><Value>
                        <AudioClip Id="9"><Name Value="GEL"/>
                          <SampleRef><FileRef><Path Value="/gel.wav"/></FileRef></SampleRef></AudioClip>
                      </Value></ClipSlot></ClipSlot>
                    </ClipSlotList>
                  </FreezeSequencer>
                </DeviceChain>
              </AudioTrack>
              <MidiTrack Id="2"><Name><EffectiveName Value="2-MIDI"/></Name></MidiTrack>
              <AudioTrack Id="3">
                <Name><EffectiveName Value="3-Audio"/><UserName Value=""/></Name>
                <DeviceChain><MainSequencer><ClipSlotList>
                  <ClipSlot Id="0"><ClipSlot><Value>
                    <AudioClip Id="2" Time="0">
                      <Name Value="Ambiance"/>
                      <Loop><LoopOn Value="true"/></Loop>
                      <SampleRef><FileRef><RelativePath Value="Samples/ambiance.aif"/></FileRef></SampleRef>
                    </AudioClip>
                  </Value></ClipSlot></ClipSlot>
                </ClipSlotList></MainSequencer></DeviceChain>
              </AudioTrack>
            </Tracks>
            <Scenes><Scene Id="0"/><Scene Id="1"/><Scene Id="2"/></Scenes>
          </LiveSet>
        </Ableton>
        """

    /// Gzip valide autour d'un XML : en-tête, flux deflate brut (`.zlib` de Compression), pied (CRC non vérifié, taille).
    static func gzip(_ text: String, withName name: String? = nil) throws -> Data {
        let raw = Data(text.utf8)
        let deflated = try (raw as NSData).compressed(using: .zlib) as Data
        var out = Data([0x1F, 0x8B, 8, name == nil ? 0 : 0x08, 0, 0, 0, 0, 0, 3])
        if let name { out.append(Data(name.utf8)); out.append(0) }
        out.append(deflated)
        out.append(contentsOf: [0, 0, 0, 0])  // CRC-32 (ignoré)
        let size = UInt32(raw.count)
        out.append(contentsOf: [UInt8(size & 0xFF), UInt8((size >> 8) & 0xFF), UInt8((size >> 16) & 0xFF), UInt8((size >> 24) & 0xFF)])
        return out
    }
}

@Suite("Lecture d'un Live Set")
struct AbletonLiveSetReaderTests {
    @Test("Pistes audio, clips par scène, boucle et références de son")
    func parsesTracksAndClips() throws {
        let set = try AbletonLiveSetReader.parse(xml: Data(LiveSetFixture.twoTracks.utf8))

        #expect(set.creator == "Ableton Live 12.1.5 Suite")
        #expect(set.sceneCount == 3)
        #expect(set.ignoredMidiTrackCount == 1)
        #expect(set.audioTracks.map(\.name) == ["Rires", "3-Audio"])  // nom utilisateur, sinon nom effectif

        let rires = set.audioTracks[0]
        #expect(Set(rires.clips.keys) == [0, 2])  // la scène 1 est vide ; le gel (FreezeSequencer) est ignoré
        #expect(rires.clips[0]?.name == "Petit rire")
        #expect(rires.clips[0]?.loops == false)
        #expect(rires.clips[0]?.sample == AbletonSampleReference(
            relativePath: "Samples/Imported/rire.wav", absolutePath: "/Users/x/Projet/Samples/Imported/rire.wav", fileName: "rire.wav"))
        #expect(rires.clips[2]?.name == "applaudissements")  // clip sans nom : nom du fichier sans extension
        #expect(rires.clips[2]?.sample?.relativePath == "")

        #expect(set.audioTracks[1].clips[0]?.loops == true)
        #expect(set.clipCount == 3)
        #expect(set.usedSceneCount == 3)
    }

    @Test("Pas un Live Set : XML quelconque, ou XML cassé")
    func rejectsOtherXML() {
        #expect(throws: AbletonImportError.notALiveSet) { try AbletonLiveSetReader.parse(xml: Data("<html></html>".utf8)) }
        #expect(throws: AbletonImportError.unreadableXML) { try AbletonLiveSetReader.parse(xml: Data("<Ableton><LiveSet>".utf8)) }
    }

    @Test("Un set sans clip se lit quand même")
    func emptySet() throws {
        let xml = "<Ableton Creator=\"Ableton Live 12.0\"><LiveSet><Tracks/><Scenes/></LiveSet></Ableton>"
        let set = try AbletonLiveSetReader.parse(xml: Data(xml.utf8))
        #expect(set.audioTracks.isEmpty)
        #expect(set.usedSceneCount == 1)
        #expect(!set.exceedsSingleGrid)
    }

    @Test("Un .als (XML en gzip) se lit de bout en bout, avec ou sans nom de fichier dans l'en-tête gzip")
    func readsGzip() throws {
        for name in [nil, "Projet.als"] {
            let data = try LiveSetFixture.gzip(LiveSetFixture.twoTracks, withName: name)
            let set = try AbletonLiveSetReader.read(fileData: data)
            #expect(set.audioTracks.count == 2)
        }
    }

    @Test("Fichiers refusés : pas du gzip, gzip tronqué, taille annoncée démesurée")
    func rejectsBadArchives() throws {
        #expect(throws: AbletonImportError.notAGzipFile) { try AbletonLiveSetReader.read(fileData: Data(Array("<Ableton/>".utf8) + Array(repeating: 0x20, count: 30))) }
        var good = try LiveSetFixture.gzip(LiveSetFixture.twoTracks)
        // Flux deflate invalide (type de bloc 3 réservé) entre un en-tête et un pied corrects.
        let garbage = Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3] + Array(repeating: UInt8(0xFF), count: 20) + [0, 0, 0, 0, 10, 0, 0, 0])
        #expect(throws: AbletonImportError.corruptArchive) { try AbletonLiveSetReader.read(fileData: garbage) }
        good.replaceSubrange((good.count - 4)..<good.count, with: [0xFF, 0xFF, 0xFF, 0x7F])  // taille annoncée ≈ 2 Gio
        #expect(throws: AbletonImportError.tooLarge) { try AbletonLiveSetReader.read(fileData: good) }
    }
}
