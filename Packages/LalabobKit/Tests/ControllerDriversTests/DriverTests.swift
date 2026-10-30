import LalabobMIDI
import LalabobModel
import Testing
@testable import ControllerDrivers

@Suite("Pilote Launchpad")
struct LaunchpadDriverTests {
    let driver = LaunchpadDriver(model: .launchpadX)

    @Test("Coins de la grille en mode Programmeur")
    func corners() {
        #expect(driver.note(for: GridPosition(column: 0, row: 7)) == 11)  // bas gauche
        #expect(driver.note(for: GridPosition(column: 7, row: 7)) == 18)  // bas droite
        #expect(driver.note(for: GridPosition(column: 0, row: 0)) == 81)  // haut gauche
        #expect(driver.note(for: GridPosition(column: 7, row: 0)) == 88)  // haut droite
    }

    @Test("Toutes les cases font l'aller-retour case → note → case")
    func roundTrip() {
        for position in GridPosition.all {
            #expect(driver.position(forNote: driver.note(for: position)) == position)
        }
    }

    @Test("Les boutons hors grille sont ignorés", arguments: [UInt8(0), 10, 19, 89, 91, 99])
    func outsideGrid(note: UInt8) {
        #expect(driver.position(forNote: note) == nil)
    }

    @Test("Passage en mode Programmeur à la connexion")
    func programmerMode() {
        #expect(driver.connectionMessages.first == .systemExclusive([0xF0, 0x00, 0x20, 0x29, 0x02, 0x0C, 0x0E, 0x01, 0xF7]))
    }

    @Test("LED en RVB 7 bits")
    func rgbLED() {
        let messages = driver.ledMessages([GridPosition(column: 0, row: 7): .lit(.rouge, .full)])
        // Rouge vif FF5C66 → 7F 2E 33
        #expect(messages == [.systemExclusive([0xF0, 0x00, 0x20, 0x29, 0x02, 0x0C, 0x03, 0x03, 11, 0x7F, 0x2E, 0x33, 0xF7])])
    }

    @Test("Les 64 LED tiennent en un seul message")
    func batching() {
        let all = Dictionary(uniqueKeysWithValues: GridPosition.all.map { ($0, LEDState.lit(.vert, .half)) })
        #expect(driver.ledMessages(all).count == 1)
    }

    @Test("Appui et relâchement")
    func input() {
        #expect(driver.interpret(.noteOn(channel: 0, note: 81, velocity: 90)) == .padPressed(GridPosition(column: 0, row: 0), velocity: 90))
        #expect(driver.interpret(.noteOff(channel: 0, note: 18, velocity: 0)) == .padReleased(GridPosition(column: 7, row: 7)))
    }
}

@Suite("Pilote APC mini mk2")
struct APCMiniMK2DriverTests {
    let driver = APCMiniMK2Driver()

    @Test("Coins de la grille")
    func corners() {
        #expect(driver.note(for: GridPosition(column: 0, row: 7)) == 0)
        #expect(driver.note(for: GridPosition(column: 7, row: 7)) == 7)
        #expect(driver.note(for: GridPosition(column: 0, row: 0)) == 56)
        #expect(driver.note(for: GridPosition(column: 7, row: 0)) == 63)
    }

    @Test("Toutes les cases font l'aller-retour case → note → case")
    func roundTrip() {
        for position in GridPosition.all {
            #expect(driver.position(forNote: driver.note(for: position)) == position)
        }
    }

    @Test("Les 8 faders de colonne sont lus, le 9e est ignoré")
    func faders() {
        #expect(driver.interpret(.controlChange(channel: 0, controller: 48, value: 127)) == .columnFader(column: 0, value: 1))
        #expect(driver.interpret(.controlChange(channel: 0, controller: 55, value: 0)) == .columnFader(column: 7, value: 0))
        #expect(driver.interpret(.controlChange(channel: 0, controller: 56, value: 64)) == nil)
    }

    @Test("Luminosité portée par le canal, couleur par la vélocité")
    func led() {
        let messages = driver.ledMessages([GridPosition(column: 0, row: 7): .lit(.rouge, .full)])
        #expect(messages == [.noteOn(channel: 6, note: 0, velocity: Tint.rouge.spec.paletteVelocity)])
    }
}

@Suite("Catalogue des contrôleurs")
struct ControllerModelTests {
    @Test("Chaque modèle fournit un pilote du bon modèle", arguments: ControllerModel.allCases)
    func drivers(model: ControllerModel) {
        #expect(model.driver.model == model)
    }
}
