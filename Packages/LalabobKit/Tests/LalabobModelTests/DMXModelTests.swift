import Foundation
import Testing

@testable import LalabobModel

/// Lumière autonome en DMX : modèle, profil de la barre, format version 4 (J14, étape 2, ADR 0012).
@Suite("Lumière DMX · modèle")
struct DMXModelTests {
    // MARK: - Couleurs (teinte + saturation, jamais un code RVB)

    @Test("La roue des couleurs : teinte et saturation donnent le rouge, le vert, le bleu, le jaune, le blanc")
    func colorWheel() {
        #expect(LightColor(hue: 0, saturation: 1).rgb == RGB(red: 255, green: 0, blue: 0))
        #expect(LightColor(hue: 120, saturation: 1).rgb == RGB(red: 0, green: 255, blue: 0))
        #expect(LightColor(hue: 240, saturation: 1).rgb == RGB(red: 0, green: 0, blue: 255))
        #expect(LightColor(hue: 60, saturation: 1).rgb == RGB(red: 255, green: 255, blue: 0))
        #expect(LightColor(hue: 180, saturation: 0).rgb == .white)
        #expect(LightColor(hue: 0, saturation: 0.5).rgb == RGB(red: 255, green: 128, blue: 128))
        #expect(LightColor.white.rgb == .white)
    }

    @Test("Teinte ramenée dans 0…360, saturation bornée à 0…1")
    func colorNormalized() {
        #expect(LightColor(hue: 360, saturation: 1) == LightColor(hue: 0, saturation: 1))
        #expect(LightColor(hue: -90, saturation: 1).hue == 270)
        #expect(LightColor(hue: 725, saturation: 1).hue == 5)
        #expect(LightColor(hue: 10, saturation: 3).saturation == 1)
        #expect(LightColor(hue: 10, saturation: -1).saturation == 0)
        #expect(LightColor(hue: .nan, saturation: .infinity) == LightColor(hue: 0, saturation: 1))
    }

    // MARK: - Profil de la barre (Chauvet DJ 4BAR LT BT, 15 canaux, relevé du 27/11/2026)

    @Test("Le profil intégré suit le tableau du manuel : programme, gradateur, strobo, puis R V B × 4")
    func barLayout() {
        let bar = FixtureProfile.chauvet4BarLTBT
        #expect(bar.channelCount == 15)
        #expect(bar.headCount == 4)
        #expect(bar.channelOffset(.program) == 0)
        #expect(bar.channelOffset(.dimmer) == 1)
        #expect(bar.channelOffset(.strobe) == 2)
        #expect(bar.channelOffset(.red, head: 1) == 3)
        #expect(bar.channelOffset(.green, head: 1) == 4)
        #expect(bar.channelOffset(.blue, head: 1) == 5)
        #expect(bar.channelOffset(.red, head: 4) == 12)
        #expect(bar.channelOffset(.blue, head: 4) == 14)
        #expect(bar.channelOffset(.red, head: 5) == nil)
        #expect(bar.channelOffset(.red) == nil)
    }

    @Test("Strobo : 0 = aucun (valeurs 0–9), sinon de lent (10) à rapide (255), toujours croissant")
    func strobeValues() {
        let bar = FixtureProfile.chauvet4BarLTBT
        #expect(bar.strobeValue(speed: 0) == 0)
        #expect(bar.strobeValue(speed: 0.001) >= 10)
        #expect(bar.strobeValue(speed: 1) == 255)
        #expect(bar.strobeValue(speed: 7) == 255)
        #expect(bar.strobeValue(speed: -1) == 0)
        let values = stride(from: 0.01, through: 1.0, by: 0.01).map { bar.strobeValue(speed: $0) }
        #expect(values == values.sorted())
        #expect(values.allSatisfy { $0 >= 10 })
    }

    @Test("Programmes de la barre : 12 numéros répartis entre 10 et 249 ; « sur le son » = 250")
    func programValues() {
        let bar = FixtureProfile.chauvet4BarLTBT
        #expect(bar.programValue(number: 1) == 10)
        #expect(bar.programValue(number: 12) == 249)
        #expect(bar.programValue(number: 0) == nil)
        #expect(bar.programValue(number: 13) == nil)
        let values = (1...12).compactMap { bar.programValue(number: $0) }
        #expect(values.count == 12 && values == values.sorted() && Set(values).count == 12)
        #expect(bar.soundActiveValue == 250)
        #expect(bar.directValue == 0)
    }

    @Test("Couleur et intensité deviennent rouge, vert, bleu ; l'intensité met les trois à l'échelle")
    func colorTranslation() {
        let bar = FixtureProfile.chauvet4BarLTBT
        #expect(bar.rgb(for: LightColor(hue: 0, saturation: 1), intensity: 1) == RGB(red: 255, green: 0, blue: 0))
        #expect(bar.rgb(for: .white, intensity: 1) == .white)
        #expect(bar.rgb(for: .white, intensity: 0) == RGB(red: 0, green: 0, blue: 0))
        #expect(bar.rgb(for: .white, intensity: 0.5) == RGB(red: 128, green: 128, blue: 128))
        #expect(bar.rgb(for: .white, intensity: 9) == .white)
        #expect(bar.rgb(for: .white, intensity: -1) == RGB(red: 0, green: 0, blue: 0))
    }

    @Test("Correction réglable à l'œil : un gamma > 1 assombrit les valeurs intermédiaires, jamais les extrêmes")
    func gammaCorrection() {
        var bar = FixtureProfile.chauvet4BarLTBT
        bar.colorGamma = 2
        #expect(bar.rgb(for: .white, intensity: 1) == .white)
        #expect(bar.rgb(for: .white, intensity: 0) == RGB(red: 0, green: 0, blue: 0))
        #expect(bar.rgb(for: .white, intensity: 0.5) == RGB(red: 64, green: 64, blue: 64))
    }

    @Test("Un profil se décrit en JSON, sans code : écrire puis relire donne le même profil")
    func profileIsData() throws {
        let bar = FixtureProfile.chauvet4BarLTBT
        let data = try JSONEncoder().encode(bar)
        #expect(try JSONDecoder().decode(FixtureProfile.self, from: data) == bar)
    }

    // MARK: - Appareil et adresse

    @Test("Adresse de départ : 1 à 498 pour 15 canaux (les 15 canaux doivent tenir dans les 512)")
    func addressRange() {
        #expect(DMXRig.addressRange(for: .chauvet4BarLTBT) == 1...498)
        #expect(DMXRig(address: 50).address == 50)
        #expect(DMXRig(address: 0).address == 1)
        #expect(DMXRig(address: 499).address == 498)
        #expect(DMXRig(address: 9999).address == 498)
    }

    @Test("Valeurs par défaut : adresse 1, noir en 1,5 s, fondu au noir à la fermeture, aucune couleur favorite")
    func rigDefaults() {
        let rig = DMXRig()
        #expect(rig.profile == .chauvet4BarLTBT)
        #expect(rig.address == 1)
        #expect(rig.blackoutFade == 1.5)
        #expect(rig.onQuit == .fadeToBlack)
        #expect(rig.favoriteColors.isEmpty)
    }

    // MARK: - États lumineux

    @Test("Couleurs, tous les projecteurs ensemble : une couleur, une intensité, le strobo arrêté par défaut")
    func uniformLook() {
        let look = LightLook.uniform(color: LightColor(hue: 30, saturation: 1), intensity: 0.8, headCount: 4)
        guard case .colors(let colors) = look.content else {
            Issue.record("contenu attendu : couleurs")
            return
        }
        #expect(colors.heads.count == 4)
        #expect(colors.heads.allSatisfy { $0.isOn && $0.color.hue == 30 && $0.intensity == 0.8 })
        #expect(colors.linked)
        #expect(colors.strobe == nil)  // jamais déclenché par erreur
        #expect(look.fadeIn == LightLook.defaultFadeIn)
    }

    @Test("Les quatre types d'états s'écrivent et se relisent à l'identique")
    func lookRoundTrip() throws {
        let looks: [LightLook] = [
            .uniform(color: LightColor(hue: 200, saturation: 0.4), intensity: 0.7, headCount: 4),
            LightLook(
                fadeIn: 2,
                content: .colors(
                    ColorsLook(
                        heads: [
                            HeadLook(isOn: true, color: .white, intensity: 1),
                            HeadLook(isOn: false, color: LightColor(hue: 0, saturation: 1), intensity: 0.3),
                            HeadLook(isOn: true, color: LightColor(hue: 120, saturation: 1), intensity: 0.5),
                            HeadLook(isOn: true, color: LightColor(hue: 240, saturation: 1), intensity: 0.9),
                        ], linked: false, strobe: 0.25))),
            LightLook(
                fadeIn: 0,
                content: .alternate(
                    AlternateLook(
                        a: LightColor(hue: 0, saturation: 1), b: LightColor(hue: 240, saturation: 1), every: .twoBeats,
                        switchFade: 0.25, fallbackBPM: 124))),
            LightLook(fadeIn: 1, content: .fixtureProgram(number: 3, speed: 0.4)),
            LightLook(fadeIn: 1, content: .soundActive(sensitivity: 0.6)),
        ]
        for look in looks {
            let data = try JSONEncoder().encode(look)
            #expect(try JSONDecoder().decode(LightLook.self, from: data) == look)
        }
    }

    @Test("Un type d'état inconnu est refusé à la lecture")
    func unknownLookType() {
        let json = #"{"fadeIn":1,"content":{"type":"laser"}}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(LightLook.self, from: Data(json.utf8)) }
    }

    // MARK: - Mode lumière et format version 4

    private func dmxShow() -> Show {
        var show = Show.new(name: "Petite salle")
        show.lighting = LightingSettings(mode: .dmx, rig: DMXRig(address: 50, favoriteColors: [LightColor(hue: 30, saturation: 0.9)]))
        let look = LightLook.uniform(color: LightColor(hue: 0, saturation: 1), intensity: 1, headCount: 4)
        show.grids[0][GridPosition(column: 7, row: 0)] = Pad.cue(title: "Plein feu", tint: .rouge, cue: LightCue(look: look))
        return show
    }

    @Test("Un spectacle d'avant le DMX s'ouvre en mode LightKey, sans changement : format 2, rien de nouveau écrit")
    func legacyShowStaysLightKey() throws {
        let show = Show.new()
        #expect(show.lighting.mode == .lightKey)
        #expect(show.lighting == LightingSettings())
        #expect(show.requiredFormatVersion == 2)
        let text = try #require(String(data: try ShowPackage.encode(show), encoding: .utf8))
        #expect(text.contains("\"formatVersion\" : 2"))
        #expect(!text.contains("lighting"))
        let data = try ShowPackage.encode(show)
        #expect(try ShowPackage.decode(data).lighting.mode == .lightKey)
    }

    @Test("Le mode Projecteurs (ou un état lumineux) demande le format 4 ; l'app de la version 3 ne le lira pas")
    func dmxNeedsVersion4() throws {
        #expect(Show.currentFormatVersion == 4)
        let show = dmxShow()
        #expect(show.requiredFormatVersion == 4)
        let text = try #require(String(data: try ShowPackage.encode(show), encoding: .utf8))
        #expect(text.contains("\"formatVersion\" : 4"))

        // Un état lumineux seul, en mode LightKey, suffit aussi : le fichier le contient.
        var onlyLook = dmxShow()
        onlyLook.lighting = LightingSettings()
        #expect(onlyLook.requiredFormatVersion == 4)

        // Même sans état lumineux, un appareil réglé (adresse 50) doit voyager.
        var onlyRig = Show.new()
        onlyRig.lighting.rig.address = 50
        #expect(onlyRig.requiredFormatVersion == 4)
    }

    @Test("Écrire puis relire un spectacle DMX redonne le même spectacle, JSON stable")
    func dmxRoundTrip() throws {
        let show = dmxShow()
        let data = try ShowPackage.encode(show)
        let read = try ShowPackage.decode(data)
        var expected = show
        expected.formatVersion = 4  // l'écriture choisit la plus petite version qui contient le spectacle
        #expect(read == expected)
        #expect(read.lighting.mode == .dmx)
        #expect(read.lighting.rig.address == 50)
        #expect(read.grids[0][GridPosition(column: 7, row: 0)]?.light?.look != nil)
        #expect(try ShowPackage.encode(read) == data)
    }

    @Test("Revenir en LightKey garde l'appareil et les états : rien n'est perdu")
    func switchingModeKeepsData() throws {
        var show = dmxShow()
        show.lighting.mode = .lightKey
        let read = try ShowPackage.decode(try ShowPackage.encode(show))
        #expect(read.lighting.rig.address == 50)
        #expect(read.grids[0][GridPosition(column: 7, row: 0)]?.light?.look != nil)
    }

    @Test("Un pad lumière garde sa note MIDI et son état lumineux : chaque mode lit sa partie")
    func cueKeepsBothTargets() {
        let look = LightLook.uniform(color: .white, intensity: 1, headCount: 4)
        let note = MIDIMessageSpec(kind: .note, channel: 0, number: 56)
        let cue = LightCue(output: note, look: look)
        #expect(cue.output == note)
        #expect(cue.look == look)
        #expect(LightCue(output: note).look == nil)
        // Un pad créé en mode DMX n'a pas encore de note : valeur neutre, jamais envoyée à LightKey tant qu'il n'est pas appairé.
        let dmxOnly = LightCue(look: look)
        #expect(dmxOnly.look == look)
        #expect(!dmxOnly.isPaired)
    }

    @Test("Un ancien fichier (cue sans état lumineux) se lit : look absent")
    func oldCueDecodes() throws {
        let json = #"{"output":{"kind":"note","channel":0,"number":56,"value":127},"behavior":"impulse","ledFeedback":true}"#
        let cue = try JSONDecoder().decode(LightCue.self, from: Data(json.utf8))
        #expect(cue.look == nil)
        #expect(cue.output.number == 56)
    }

    // MARK: - Validation (tout ce qui vient d'un fichier)

    private func rejects(_ edit: (inout Show) -> Void, sourceLocation: SourceLocation = #_sourceLocation) {
        var show = dmxShow()
        edit(&show)
        #expect(throws: ShowValidationError.self, sourceLocation: sourceLocation) { try show.validate() }
    }

    @Test("Un spectacle DMX valide passe")
    func validShowPasses() throws {
        try dmxShow().validate()
    }

    @Test("Adresse hors de 1…498 refusée")
    func invalidAddress() {
        rejects { $0.lighting.rig.address = 0 }
        rejects { $0.lighting.rig.address = 499 }
        rejects { $0.lighting.rig.address = -3 }
    }

    @Test("Fondu du noir hors de 0…10 s, trop de couleurs favorites, couleur hors bornes : refusés")
    func invalidRigValues() {
        rejects { $0.lighting.rig.blackoutFade = -1 }
        rejects { $0.lighting.rig.blackoutFade = 11 }
        rejects { $0.lighting.rig.blackoutFade = .nan }
        rejects { $0.lighting.rig.favoriteColors = Array(repeating: .white, count: DMXRig.maximumFavoriteColors + 1) }
        rejects { $0.lighting.rig.favoriteColors = [LightColor(unchecked: 400, saturation: 0.5)] }
        rejects { $0.lighting.rig.favoriteColors = [LightColor(unchecked: 10, saturation: 2)] }
    }

    @Test("Profil incohérent refusé : canal sans projecteur, canal en double, trop de canaux, plus de 16 projecteurs")
    func invalidProfile() {
        rejects { $0.lighting.rig.profile.channels = [] }
        rejects { $0.lighting.rig.profile.channels.append(FixtureChannel(role: .dimmer)) }  // deux gradateurs
        rejects { $0.lighting.rig.profile.channels[3] = FixtureChannel(role: .red, head: 0) }  // couleur sans projecteur
        rejects { $0.lighting.rig.profile.channels[0] = FixtureChannel(role: .program, head: 2) }  // programme « par projecteur »
        rejects { $0.lighting.rig.profile.channels = (0..<513).map { _ in FixtureChannel(role: .program) } }
        rejects { $0.lighting.rig.profile.strobeSlowest = 0 }
        rejects { $0.lighting.rig.profile.colorGamma = 0 }
        rejects { $0.lighting.rig.profile.colorGamma = 9 }
    }

    @Test("États lumineux hors bornes refusés : intensité, strobo, fondu, programme, tempo, sensibilité, projecteurs en trop")
    func invalidLooks() {
        func edit(_ show: inout Show, _ look: LightLook) {
            show.grids[0][GridPosition(column: 7, row: 0)]?.light?.look = look
        }
        let heads = { (intensity: Double) in
            (0..<4).map { _ in HeadLook(isOn: true, color: .white, intensity: intensity) }
        }
        rejects { edit(&$0, LightLook(fadeIn: 1, content: .colors(ColorsLook(heads: heads(1.5), linked: true, strobe: nil)))) }
        rejects { edit(&$0, LightLook(fadeIn: 1, content: .colors(ColorsLook(heads: heads(-0.1), linked: true, strobe: nil)))) }
        rejects { edit(&$0, LightLook(fadeIn: 1, content: .colors(ColorsLook(heads: heads(1), linked: true, strobe: 2)))) }
        rejects { edit(&$0, LightLook(fadeIn: 1, content: .colors(ColorsLook(heads: [], linked: true, strobe: nil)))) }
        rejects { edit(&$0, LightLook(fadeIn: 1, content: .colors(ColorsLook(heads: Array(heads(1).prefix(3)), linked: true, strobe: nil)))) }
        rejects { edit(&$0, LightLook(fadeIn: -1, content: .colors(ColorsLook(heads: heads(1), linked: true, strobe: nil)))) }
        rejects { edit(&$0, LightLook(fadeIn: 31, content: .colors(ColorsLook(heads: heads(1), linked: true, strobe: nil)))) }
        rejects { edit(&$0, LightLook(fadeIn: 1, content: .fixtureProgram(number: 0, speed: 0.5))) }
        rejects { edit(&$0, LightLook(fadeIn: 1, content: .fixtureProgram(number: 13, speed: 0.5))) }
        rejects { edit(&$0, LightLook(fadeIn: 1, content: .fixtureProgram(number: 3, speed: 1.5))) }
        rejects { edit(&$0, LightLook(fadeIn: 1, content: .soundActive(sensitivity: 2))) }
        let alternate = { (fade: Double, bpm: Double) in
            LightLook(
                fadeIn: 0,
                content: .alternate(AlternateLook(a: .white, b: .white, every: .beat, switchFade: fade, fallbackBPM: bpm)))
        }
        rejects { edit(&$0, alternate(0.9, 120)) }
        rejects { edit(&$0, alternate(0.1, 10)) }
        rejects { edit(&$0, alternate(0.1, 1000)) }
        rejects { edit(&$0, alternate(0.1, .nan)) }
    }

    @Test("Aucun état n'est jamais accepté avec une valeur non numérique")
    func nanRejected() {
        rejects { show in
            let head = HeadLook(isOn: true, color: .white, intensity: .nan)
            show.grids[0][GridPosition(column: 7, row: 0)]?.light?.look = LightLook(
                fadeIn: 1, content: .colors(ColorsLook(heads: Array(repeating: head, count: 4), linked: true, strobe: nil)))
        }
    }

    @Test("Un état lumineux est vérifié même dans une colonne mise de côté")
    func parkedLooksAreValidated() throws {
        var show = dmxShow()
        var column = Column.empty(name: "Lumière", kind: .light)
        let bad = LightLook(fadeIn: 99, content: .soundActive(sensitivity: 0.5))
        column.slots[0] = Pad.cue(title: "x", tint: .rouge, cue: LightCue(look: bad))
        show.grids[0].parkedColumns = [ParkedColumn(index: 0, column: column)]
        #expect(throws: ShowValidationError.self) { try show.validate() }
    }

    @Test("Format 5 et plus : refusé (une version future de l'app)")
    func futureVersionRefused() {
        var show = dmxShow()
        show.formatVersion = Show.currentFormatVersion + 1
        #expect(throws: ShowValidationError.unsupportedFormatVersion(5)) { try show.validate() }
    }

    @Test("Un fichier de version 3 se lit et se réécrit en version 2 ou 3 : le DMX n'est écrit que s'il sert")
    func version3StillReads() throws {
        var musicShow = Show.new()
        musicShow.grids.append(.emptyAppleMusic(name: "M"))
        musicShow.formatVersion = 3
        let data = try ShowPackage.encode(musicShow)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"formatVersion\" : 3"))
        #expect(try ShowPackage.decode(data).lighting == LightingSettings())
    }
}
