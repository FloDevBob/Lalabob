import ControllerDrivers
import Foundation
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// Fenêtre d'accueil (spec `docs/spec-fenetre-accueil.md`) : les textes de « Avant de jouer » suivent l'état du matériel,
/// les spectacles récents donnent un aperçu ou rien, jamais une erreur.
@Suite("Fenêtre d'accueil")
struct WelcomeTests {
    private static let speakers = SoundOutputFact(name: "Haut-parleurs MacBook Pro", kind: .builtInSpeakers)
    private static let jack = SoundOutputFact(name: "Écouteurs externes", kind: .headphoneJack)
    private static let usbCard = SoundOutputFact(name: "MOTU M2", kind: .other)

    private static func facts(
        output: SoundOutputFact? = jack, controller: ControllerModel? = .apcMiniMK2, dmxBox: Bool = false,
        lightKey: LightKeyState = .closed
    ) -> HardwareFacts {
        HardwareFacts(output: output, controller: controller, dmxBox: dmxBox, lightKey: lightKey)
    }

    private static func line(_ device: WelcomeChecklist.Device, in facts: HardwareFacts) -> WelcomeChecklist.Line {
        WelcomeChecklist(facts: facts).lines.first { $0.device == device }!
    }

    // MARK: Sortie audio

    @Test("Haut-parleurs, prise casque, autre sortie : d'après le transport, la source, l'identifiant et le nom")
    func classifyOutput() {
        let builtIn = AudioOutputKind.builtInTransport
        #expect(AudioOutputKind.classify(uid: "BuiltInSpeakerDevice", name: "Haut-parleurs MacBook Pro", transportType: builtIn, dataSource: AudioOutputKind.speakerSource) == .builtInSpeakers)
        #expect(AudioOutputKind.classify(uid: "BuiltInHeadphoneOutputDevice", name: "Écouteurs externes", transportType: builtIn, dataSource: AudioOutputKind.headphoneSource) == .headphoneJack)
        // Mac sans source déclarée : l'identifiant ou le nom suffit.
        #expect(AudioOutputKind.classify(uid: "BuiltInHeadphoneOutputDevice", name: "External Headphones", transportType: builtIn, dataSource: nil) == .headphoneJack)
        #expect(AudioOutputKind.classify(uid: "X", name: "MacBook Air Speakers", transportType: builtIn, dataSource: nil) == .builtInSpeakers)
        // Une carte son USB n'est jamais « le Mac lui-même », même si son nom parle de casque.
        #expect(AudioOutputKind.classify(uid: "AppleUSBAudioEngine:MOTU:M2", name: "MOTU M2", transportType: 0x7573_6220, dataSource: nil) == .other)
        #expect(AudioOutputKind.classify(uid: "AirPods", name: "Écouteurs de Flo", transportType: 0x626C_7565, dataSource: nil) == .other)
    }

    // MARK: Son

    @Test("Son sur la prise casque : prêt, nom de la sortie")
    func soundOnJack() {
        let line = Self.line(.sound, in: Self.facts(output: Self.jack))
        #expect(line.isReady)
        #expect(line.status == "Prêt")
        #expect(line.detail == "Écouteurs externes")
        #expect(line.hint == "Le son sort par la prise casque. Sortie à changer en haut de la grille.")
        #expect(line.link == nil)
    }

    @Test("Son sur une autre sortie (carte son) : prêt, sans parler de la prise casque")
    func soundOnUSBCard() {
        let line = Self.line(.sound, in: Self.facts(output: Self.usbCard))
        #expect(line.isReady)
        #expect(line.detail == "MOTU M2")
        #expect(line.hint == "Sortie à changer en haut de la grille.")
    }

    @Test("Son sur les haut-parleurs du Mac : à brancher, on dit où sort le son")
    func soundOnSpeakers() {
        let line = Self.line(.sound, in: Self.facts(output: Self.speakers))
        #expect(!line.isReady)
        #expect(line.status == "À brancher")
        #expect(line.detail == "Haut-parleurs MacBook Pro")
        #expect(line.hint == "Le son sort du Mac lui-même : branchez l’enceinte sur la prise casque (mini-jack).")
    }

    @Test("Aucune sortie audio")
    func noOutput() {
        let line = Self.line(.sound, in: Self.facts(output: nil))
        #expect(!line.isReady)
        #expect(line.detail == "Aucune sortie audio")
        #expect(line.hint == "Branchez l’enceinte sur la prise casque (mini-jack).")
    }

    // MARK: Contrôleur

    @Test("Contrôleur branché ou absent")
    func controller() {
        let ready = Self.line(.controller, in: Self.facts(controller: .launchpadMiniMK3))
        #expect(ready.isReady)
        #expect(ready.status == "Prêt")
        #expect(ready.detail == "Launchpad Mini MK3")
        #expect(ready.hint == "Reconnu, les pads s’allument à l’ouverture du spectacle.")

        let missing = Self.line(.controller, in: Self.facts(controller: nil))
        #expect(!missing.isReady)
        #expect(missing.status == "À brancher")
        #expect(missing.detail == "Aucun contrôleur")
        #expect(missing.hint == "Branchez l’APC mini mk2 ou le Launchpad Mini MK3 en USB.")
    }

    // MARK: Lumière

    @Test("Ni boîtier ni LightKey : un lien « ouvrez LightKey » dans la phrase")
    func lightNothing() {
        let line = Self.line(.light, in: Self.facts(dmxBox: false, lightKey: .closed))
        #expect(!line.isReady)
        #expect(line.status == "À préparer")
        #expect(line.detail == "Rien de détecté")
        #expect(line.hint == "Branchez le boîtier USB-DMX, ou ")
        #expect(line.link == "ouvrez LightKey")
        #expect(line.hintEnd == ".")
    }

    @Test("LightKey absent de ce Mac : pas de lien")
    func lightKeyNotInstalled() {
        let line = Self.line(.light, in: Self.facts(dmxBox: false, lightKey: .notInstalled))
        #expect(line.hint == "Branchez le boîtier USB-DMX, ou installez LightKey.")
        #expect(line.link == nil)
        #expect(line.hintEnd.isEmpty)
    }

    @Test("LightKey ouvert : prête")
    func lightKeyRunning() {
        let line = Self.line(.light, in: Self.facts(dmxBox: false, lightKey: .running))
        #expect(line.isReady)
        #expect(line.status == "Prête")
        #expect(line.detail == "LightKey ouvert")
        #expect(line.hint == "Lalabob lui envoie les appuis des colonnes lumière.")
        #expect(line.link == nil)
    }

    @Test("Boîtier USB-DMX : prête ; avec LightKey ouvert, on demande de le fermer")
    func dmxBox() {
        let alone = Self.line(.light, in: Self.facts(dmxBox: true, lightKey: .closed))
        #expect(alone.isReady)
        #expect(alone.detail == "Boîtier USB-DMX")
        #expect(alone.hint == "Lalabob pilote les projecteurs lui-même.")

        let both = Self.line(.light, in: Self.facts(dmxBox: true, lightKey: .running))
        #expect(both.isReady)
        #expect(both.detail == "Boîtier USB-DMX")
        #expect(both.hint == "Fermez LightKey : les deux enverraient à la barre.")
    }

    // MARK: Résumé

    @Test("Résumé : n sur 3, ou tout est prêt ; lignes dans l'ordre son, contrôleur, lumière")
    func summary() {
        let partial = WelcomeChecklist(facts: Self.facts())
        #expect(partial.lines.map(\.device) == [.sound, .controller, .light])
        #expect(partial.readyCount == 2)
        #expect(partial.summary == "2 sur 3 prêts")
        #expect(!partial.isAllReady)

        let none = WelcomeChecklist(facts: Self.facts(output: Self.speakers, controller: nil))
        #expect(none.summary == "Rien n’est prêt")

        let one = WelcomeChecklist(facts: Self.facts(controller: nil))
        #expect(one.summary == "1 sur 3 prêt")

        let all = WelcomeChecklist(facts: Self.facts(lightKey: .running))
        #expect(all.summary == "Tout est prêt")
        #expect(all.isAllReady)
    }

    // MARK: État en direct

    @Test("L'état lit le matériel à chaque rafraîchissement")
    @MainActor
    func hardwareStatusRefresh() {
        var box = false
        var controller: ControllerModel? = nil
        let status = HardwareStatus(
            probe: HardwareProbe(output: { Self.jack }, dmxBox: { box }, lightKey: { .closed }),
            controller: { controller })
        status.refresh()
        #expect(status.facts == Self.facts(controller: nil))
        box = true
        controller = .apcMiniMK2
        status.refresh()
        #expect(status.facts == Self.facts(controller: .apcMiniMK2, dmxBox: true))
        #expect(status.checklist.isAllReady)
    }

    @Test("La session MIDI dit quel contrôleur est branché, même sans spectacle ouvert")
    @MainActor
    func sessionWithoutShow() async {
        let transport = FakeMIDITransport()
        let session = ControllerSession(transport: transport)
        let runner = Task { await session.run() }
        defer { runner.cancel() }
        #expect(session.connectedModel == nil)
        await transport.setPorts(
            sources: [MIDIPort(id: MIDIPortID(uniqueID: 201), name: "APC mini mk2 Control In", groupID: 21)],
            destinations: [MIDIPort(id: MIDIPortID(uniqueID: 202), name: "APC mini mk2 Control Out", groupID: 21)])
        #expect(await waitUntil { await session.connectedModel == .apcMiniMK2 })
        await transport.setPorts(sources: [], destinations: [])
        #expect(await waitUntil { await session.connectedModel == nil })
    }

    // MARK: Spectacles récents

    private func makePackage(_ show: Show?, raw: Data? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "lalabob-recent-\(UUID().uuidString).lalabob")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let show { try ShowPackage.encode(show).write(to: url.appending(path: ShowPackage.showFileName)) }
        if let raw { try raw.write(to: url.appending(path: ShowPackage.showFileName)) }
        return url
    }

    @Test("Un paquet lisible donne son aperçu")
    func recentPreview() throws {
        var grid = PadGrid.empty(name: "G")
        grid.columns[0].slots[0] = .sound(title: "A", tint: .vert, clip: AudioClip(fileName: "a.wav"))
        let url = try makePackage(Show(name: "Cabaret", grids: [grid]))
        defer { try? FileManager.default.removeItem(at: url) }
        let preview = try #require(RecentShowPreview.load(packageURL: url))
        #expect(preview.cells[0] == .tint(.vert))
        #expect(preview.summary == "1 son · 1 grille")
    }

    @Test("Paquet abîmé, sans show.json, ou absent : pas d'aperçu, pas d'erreur")
    func recentPreviewFailures() throws {
        let corrupt = try makePackage(nil, raw: Data("pas du json".utf8))
        let empty = try makePackage(nil)
        defer {
            try? FileManager.default.removeItem(at: corrupt)
            try? FileManager.default.removeItem(at: empty)
        }
        #expect(RecentShowPreview.load(packageURL: corrupt) == nil)
        #expect(RecentShowPreview.load(packageURL: empty) == nil)
        #expect(RecentShowPreview.load(packageURL: URL(filePath: "/nulle/part.lalabob")) == nil)
    }

    @Test("Date d'un récent : aujourd'hui, hier, sinon jour et mois")
    func recentDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 15)))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: 9)))
        let yesterday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 23)))
        let older = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 12)))
        let lastYear = try #require(calendar.date(from: DateComponents(year: 2025, month: 9, day: 3, hour: 12)))
        #expect(RecentShowPreview.dateLabel(for: today, now: now, calendar: calendar) == "Aujourd’hui")
        #expect(RecentShowPreview.dateLabel(for: yesterday, now: now, calendar: calendar) == "Hier")
        #expect(RecentShowPreview.dateLabel(for: older, now: now, calendar: calendar) == "21 nov.")
        #expect(RecentShowPreview.dateLabel(for: lastYear, now: now, calendar: calendar) == "3 sept. 2025")
    }
}
