import LalabobMIDI
import Testing

@testable import ControllerDrivers

@Suite("Détection des contrôleurs")
struct DetectionTests {
    @Test(
        "Reconnaissance par nom de port",
        arguments: [
            ("Launchpad X LPX MIDI", ControllerModel.launchpadX),
            ("Launchpad Mini MK3 LPMiniMK3 MIDI", .launchpadMiniMK3),
            ("Launchpad Pro MK3 LPProMK3 MIDI", .launchpadProMK3),
            ("APC mini mk2 Control", .apcMiniMK2),
            ("APC MINI MK2", .apcMiniMK2),
            ("launchpad x lpx midi", .launchpadX),
        ])
    func byName(name: String, expected: ControllerModel) {
        #expect(ControllerModel.detect(portName: name) == expected)
    }

    @Test("Un port inconnu n'est pas un contrôleur", arguments: ["IAC Driver Bus 1", "Lalabob Lumière", "", "Launchpad"])
    func unknown(name: String) {
        #expect(ControllerModel.detect(portName: name) == nil)
    }

    @Test("Le Launchpad : on utilise le port MIDI, pas le port DAW")
    func launchpadPorts() {
        #expect(ControllerModel.launchpadX.isControlPort(named: "Launchpad X LPX MIDI"))
        #expect(!ControllerModel.launchpadX.isControlPort(named: "Launchpad X LPX DAW"))
        #expect(!ControllerModel.launchpadMiniMK3.isControlPort(named: "Launchpad Mini MK3 LPMiniMK3 DAW"))
    }

    @Test("L'APC n'a qu'un port de contrôle")
    func apcPorts() {
        #expect(ControllerModel.apcMiniMK2.isControlPort(named: "APC mini mk2 Control"))
    }

    @Test("Le fabricant de la réponse d'identité confirme le modèle")
    func manufacturerConsistency() {
        let novation = DeviceInquiry.Reply(manufacturer: [0x00, 0x20, 0x29], family: [0x03, 0x01])
        let akai = DeviceInquiry.Reply(manufacturer: [0x47], family: [0x4F, 0x00])
        #expect(ControllerModel.launchpadX.isConsistent(with: novation))
        #expect(ControllerModel.launchpadProMK3.isConsistent(with: novation))
        #expect(!ControllerModel.launchpadX.isConsistent(with: akai))
        #expect(ControllerModel.apcMiniMK2.isConsistent(with: akai))
        #expect(!ControllerModel.apcMiniMK2.isConsistent(with: novation))
    }

    @Test("Une réponse d'identité Novation est reconnue (octets de test, pas relevés sur le matériel)")
    func parsesNovationReply() throws {
        let bytes: [UInt8] = [0xF0, 0x7E, 0x00, 0x06, 0x02, 0x00, 0x20, 0x29, 0x03, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0xF7]
        let reply = try #require(DeviceInquiry.parseReply(bytes))
        #expect(ControllerModel.launchpadX.isConsistent(with: reply))
    }
}
