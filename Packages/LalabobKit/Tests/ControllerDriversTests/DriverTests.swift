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

@Suite("Faders renvoyés vers LightKey")
struct FaderEventTests {
    let apc = APCMiniMK2Driver()

    @Test("L'APC envoie le CC du fader de la colonne (48 + colonne), valeur sur 7 bits")
    func apcFaderEvents() {
        #expect(apc.faderEvent(column: 6, value: 1) == .controlChange(channel: 0, controller: 54, value: 127))
        #expect(apc.faderEvent(column: 7, value: 0) == .controlChange(channel: 0, controller: 55, value: 0))
        #expect(apc.faderEvent(column: 0, value: 0.5) == .controlChange(channel: 0, controller: 48, value: 64))
    }

    @Test("Les valeurs hors 0…1 ou invalides sont bornées")
    func clampedValues() {
        #expect(apc.faderEvent(column: 6, value: 3) == .controlChange(channel: 0, controller: 54, value: 127))
        #expect(apc.faderEvent(column: 6, value: -1) == .controlChange(channel: 0, controller: 54, value: 0))
        #expect(apc.faderEvent(column: 6, value: .nan) == .controlChange(channel: 0, controller: 54, value: 0))
    }

    @Test("Seules les 8 colonnes ont un fader ; le 9e (maître) n'est jamais produit")
    func columnRange() {
        #expect(apc.faderEvent(column: -1, value: 1) == nil)
        #expect(apc.faderEvent(column: 8, value: 1) == nil)
    }

    @Test("Ce que l'APC envoie, le pilote le relit à l'identique")
    func roundTrip() {
        for column in 0..<8 {
            guard let event = apc.faderEvent(column: column, value: 1) else { Issue.record("pas d'événement"); continue }
            #expect(apc.interpret(event) == .columnFader(column: column, value: 1))
        }
    }

    @Test("Un Launchpad n'a pas de fader")
    func launchpadHasNone() {
        #expect(LaunchpadDriver(model: .launchpadX).faderEvent(column: 6, value: 1) == nil)
    }
}

@Suite("Catalogue des contrôleurs")
struct ControllerModelTests {
    @Test("Chaque modèle fournit un pilote du bon modèle", arguments: ControllerModel.allCases)
    func drivers(model: ControllerModel) {
        #expect(model.driver.model == model)
    }
}

/// Retour de LightKey : Note On = cue allumée, Note Off = éteinte (relevé du 01/11/2026, APC mini mk2).
@Suite("Retour de LightKey")
struct LightFeedbackTests {
    private let apc = APCMiniMK2Driver()

    @Test("Note On = allumée, Note Off = éteinte, sur la case de la note")
    func onAndOff() throws {
        // Note 63 = rangée du bas + 7 → colonne 7, en haut ; note 23 = colonne 7, 3e rangée en partant du bas.
        let on = try #require(apc.lightFeedback(for: .noteOn(channel: 0, note: 63, velocity: 127)))
        #expect(on.position == GridPosition(column: 7, row: 0))
        #expect(on.state == .on)
        let off = try #require(apc.lightFeedback(for: .noteOff(channel: 0, note: 23, velocity: 0)))
        #expect(off.position == GridPosition(column: 7, row: 5))
        #expect(off.state == .off)
    }

    @Test("Un Note On de vélocité 0 est éteint, le canal est sans importance")
    func zeroVelocityAndChannel() throws {
        let zero = try #require(apc.lightFeedback(for: .noteOn(channel: 0, note: 14, velocity: 0)))
        #expect(zero.state == .off)
        let channel = try #require(apc.lightFeedback(for: .noteOn(channel: 15, note: 14, velocity: 127)))
        #expect(channel.state == .on)
        #expect(channel.position == zero.position)
    }

    @Test("Hors grille ou autre type de message : ignoré")
    func ignored() {
        #expect(apc.lightFeedback(for: .noteOn(channel: 0, note: 64, velocity: 127)) == nil)
        #expect(apc.lightFeedback(for: .controlChange(channel: 0, controller: 54, value: 100)) == nil)
        #expect(apc.lightFeedback(for: .systemExclusive([0xF0, 0x01, 0xF7])) == nil)
    }

    @Test("Le Launchpad utilise ses propres notes")
    func launchpad() throws {
        let launchpad = LaunchpadDriver(model: .launchpadX)
        let result = try #require(launchpad.lightFeedback(for: .noteOn(channel: 0, note: 81, velocity: 127)))
        #expect(result.position == GridPosition(column: 0, row: 0))
        #expect(result.state == .on)
    }
}
