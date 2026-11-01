import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// L'étalonnage des LED du Launchpad : mémorisé, appliqué aux couleurs envoyées, renvoyé à chaque changement.
@MainActor
@Suite("Étalonnage des LED (session)", .serialized)
struct LEDCalibrationSessionTests {
    private let corner = GridPosition(column: 0, row: 7)

    private func makeController() -> ShowController {
        var grid = PadGrid.empty(name: "G")
        grid[corner] = Pad(title: "Rire", tint: .rouge, content: .audio(clip: AudioClip(fileName: "a.wav")))
        return ShowController(
            show: Show(name: "S", grids: [grid]), audio: RecordingAudioEngine(),
            audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
    }

    /// Les octets RVB envoyés pour la case en bas à gauche (note 11), d'après les SysEx reçus par le Launchpad.
    private func lastRGB(_ events: [MIDIEvent]) -> [UInt8]? {
        for event in events.reversed() {
            guard case .systemExclusive(let bytes) = event, bytes.count > 7, bytes[6] == 0x03 else { continue }
            var index = 7
            while index + 4 < bytes.count {
                if bytes[index] == 0x03, bytes[index + 1] == 11 { return Array(bytes[index + 2...index + 4]) }
                index += bytes[index] == 0x03 ? 5 : bytes[index] == 0x02 ? 3 : 3
            }
        }
        return nil
    }

    private func plugLaunchpad(_ transport: FakeMIDITransport, _ controller: ShowController) async {
        await transport.setPorts(
            sources: [ControllerSessionTests.lpxSource], destinations: [ControllerSessionTests.lpxDestination])
        _ = await waitUntil { await controller.connectedController == .launchpadX }
    }

    /// Le nombre de SysEx « pad RVB » (APC mini mk2) reçus par le contrôleur.
    private func rgbSysExCount(_ transport: FakeMIDITransport, _ destination: MIDIPortID) async -> Int {
        await transport.sentEvents(to: destination).filter {
            if case .systemExclusive(let bytes) = $0 { bytes.starts(with: [0xF0, 0x47, 0x7F, 0x4F, 0x24]) } else { false }
        }.count
    }

    @Test("Au départ, l'étalonnage standard est appliqué aux couleurs envoyées au Launchpad")
    func startsWithTheStandardCalibration() async {
        let defaults = UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!
        let controller = makeController()
        let transport = FakeMIDITransport()
        let session = ControllerSession(controller: controller, transport: transport, defaults: defaults)
        let runner = Task { await session.run() }
        defer { runner.cancel() }
        await plugLaunchpad(transport, controller)

        #expect(session.ledSettings(for: .launchpadX) == .standard)
        let expected = LEDCalibration.standard.apply(to: Tint.rouge.spec.vivid)
        #expect(await waitUntil { await self.lastRGB(transport.sentEvents(to: ControllerSessionTests.lpxDestination.id)) != nil })
        let rgb = lastRGB(await transport.sentEvents(to: ControllerSessionTests.lpxDestination.id))
        #expect(rgb == [expected.red >> 1, expected.green >> 1, expected.blue >> 1])
    }

    @Test("Changer l'étalonnage renvoie les LED avec les nouvelles couleurs, et le réglage est mémorisé")
    func changingTheCalibrationResendsAndPersists() async {
        let defaults = UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!
        let controller = makeController()
        let transport = FakeMIDITransport()
        let session = ControllerSession(controller: controller, transport: transport, defaults: defaults)
        let runner = Task { await session.run() }
        defer { runner.cancel() }
        await plugLaunchpad(transport, controller)
        _ = await waitUntil { await self.lastRGB(transport.sentEvents(to: ControllerSessionTests.lpxDestination.id)) != nil }
        let before = lastRGB(await transport.sentEvents(to: ControllerSessionTests.lpxDestination.id))

        session.setLEDSettings(.neutral, for: .launchpadX)
        let vivid = Tint.rouge.spec.vivid
        let raw: [UInt8] = [vivid.red >> 1, vivid.green >> 1, vivid.blue >> 1]
        #expect(await waitUntil { await self.lastRGB(transport.sentEvents(to: ControllerSessionTests.lpxDestination.id)) == raw })
        #expect(before != raw)

        // Un nouveau lancement retrouve le réglage.
        let relaunched = ControllerSession(transport: FakeMIDITransport(), defaults: defaults)
        #expect(relaunched.ledSettings(for: .launchpadX) == .neutral)
        #expect(relaunched.ledSettings(for: .apcMiniMK2) == .standard)  // chaque famille a ses réglages
    }

    @Test("Un réglage abîmé ou hors plage est ramené dans les bornes")
    func damagedSettingsAreClamped() {
        let defaults = UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!
        defaults.set(Data("pas du json".utf8), forKey: ControllerSession.settingsDefaultsKey)
        #expect(ControllerSession(transport: FakeMIDITransport(), defaults: defaults).ledSettings(for: .launchpadX) == .standard)

        let session = ControllerSession(transport: FakeMIDITransport(), defaults: defaults)
        session.setLEDSettings(LEDSettings(calibration: LEDCalibration(saturation: 50, gamma: 0, brightness: 50)), for: .launchpadX)
        #expect(session.ledSettings(for: .launchpadX).calibration == LEDCalibration(saturation: 2, gamma: 1, brightness: 1.5))
    }

    @Test("APC mini mk2 : passer en RVB libre éteint la grille puis renvoie les couleurs en SysEx ; revenir à la palette aussi")
    func apcRGBModeSwitch() async {
        let defaults = UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!
        let controller = makeController()
        let transport = FakeMIDITransport()
        let session = ControllerSession(controller: controller, transport: transport, defaults: defaults)
        let runner = Task { await session.run() }
        defer { runner.cancel() }
        await transport.setPorts(sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
        _ = await waitUntil { await controller.connectedController == .apcMiniMK2 }
        let destination = ControllerSessionTests.apcDestination.id

        #expect(await self.rgbSysExCount(transport, destination) == 0)  // palette par défaut : aucun SysEx

        session.setLEDSettings(LEDSettings(calibration: .standard, usesRGB: true), for: .apcMiniMK2)
        #expect(await waitUntil { await self.rgbSysExCount(transport, destination) >= 64 })  // 64 pads éteints, puis le pad allumé
        #expect(session.ledSettings(for: .apcMiniMK2).usesRGB)
        #expect(!session.ledSettings(for: .launchpadX).usesRGB)  // l'autre famille n'est pas touchée

        await transport.clearSent()
        session.setLEDSettings(LEDSettings(calibration: .standard, usesRGB: false), for: .apcMiniMK2)
        #expect(await waitUntil { await transport.sentEvents(to: destination).count >= 64 })
        #expect(await self.rgbSysExCount(transport, destination) == 0)
    }
}
