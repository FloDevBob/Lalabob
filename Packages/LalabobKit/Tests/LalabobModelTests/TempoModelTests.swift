import Foundation
import Testing

@testable import LalabobModel

/// Tempo d'un son corrigé à la main et avance de la lumière (J14, étape 3b) : enregistrement et validation.
@Suite("Tempo des sons · modèle")
struct TempoModelTests {
    @Test("Grille de temps : tempo borné, premier temps ramené dans la première période")
    func beatGrid() {
        #expect(BeatGrid(bpm: 120, firstBeat: 1.3).firstBeat == 1.3.truncatingRemainder(dividingBy: 0.5))
        #expect(abs(BeatGrid(bpm: 120, firstBeat: -0.1).firstBeat - 0.4) < 1e-12)
        #expect(BeatGrid(bpm: 1000, firstBeat: 0).bpm == 300)
        #expect(BeatGrid(bpm: .nan, firstBeat: 0).bpm == 120)
    }

    @Test("Un son sans correction n'écrit rien ; « pas de tempo » et un tempo manuel s'enregistrent")
    func roundTrip() throws {
        let plain = AudioClip(fileName: "a.wav")
        let encoded = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!encoded.contains("tempo"))
        for tempo in [SoundTempo.none, .manual(BeatGrid(bpm: 96, firstBeat: 0.2))] {
            let clip = AudioClip(fileName: "a.wav", tempo: tempo)
            #expect(try JSONDecoder().decode(AudioClip.self, from: JSONEncoder().encode(clip)) == clip)
        }
    }

    @Test("Un tempo hors bornes dans le fichier est refusé")
    func validation() throws {
        let json = #"{"fileName":"a.wav","trimStart":0,"loops":false,"retrigger":"restart","gainDB":0,"tempo":{"type":"manual","grid":{"bpm":9000,"firstBeat":0}}}"#
        let clip = try JSONDecoder().decode(AudioClip.self, from: Data(json.utf8))
        var grid = PadGrid.empty(name: "G")
        grid.columns[0].slots[0] = Pad(title: "A", tint: .rouge, audio: clip)
        #expect(throws: ShowValidationError.self) { try Show(name: "S", grids: [grid]).validate() }
    }

    @Test("Avance de la lumière : absente des anciens fichiers = 0 ; bornée ; refusée hors bornes")
    func lightLead() throws {
        let rig = DMXRig()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(rig)) as? [String: Any])
        object["lightLead"] = nil
        let decoded = try JSONDecoder().decode(DMXRig.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.lightLead == 0)
        #expect(DMXRig(lightLead: 3).lightLead == 0.5)
        object["lightLead"] = 4
        let tooMuch = try JSONDecoder().decode(DMXRig.self, from: JSONSerialization.data(withJSONObject: object))
        var show = Show(name: "S", grids: [PadGrid.empty(name: "G")])
        show.lighting.rig = tooMuch
        #expect(throws: ShowValidationError.self) { try show.validate() }
    }
}
