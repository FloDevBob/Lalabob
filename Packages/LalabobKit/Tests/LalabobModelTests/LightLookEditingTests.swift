import Testing

@testable import LalabobModel

@Suite("Édition d'un état lumineux")
struct LightLookEditingTests {
    let profile = FixtureProfile.chauvet4BarLTBT
    let red = LightColor(hue: 0, saturation: 1)
    let blue = LightColor(hue: 240, saturation: 1)

    func colorsLook(_ colors: [LightColor], fade: Double = 2) -> LightLook {
        let heads = colors.map { HeadLook(isOn: true, color: $0, intensity: 0.8) }
        return LightLook(fadeIn: fade, content: .colors(ColorsLook(heads: heads, linked: false, strobe: nil)))
    }

    @Test("La barre de la troupe sait jouer les quatre types")
    func supportedKinds() {
        #expect(profile.supportedLookStyles == [.colors, .alternate, .fixtureProgram, .soundActive])
        var bare = profile
        bare.programs = nil
        bare.soundActiveValue = nil
        #expect(bare.supportedLookStyles == [.colors, .alternate])
        #expect(LightLook.uniform(color: red, intensity: 1, headCount: 4).converted(to: .fixtureProgram, profile: bare) == nil)
    }

    @Test("Couleurs → alternance : les deux premières couleurs deviennent A et B ; le fondu reste")
    func colorsToAlternate() throws {
        let look = try #require(colorsLook([red, blue, red, blue]).converted(to: .alternate, profile: profile))
        guard case .alternate(let alternate) = look.content else { Issue.record("pas une alternance"); return }
        #expect(alternate.a == red)
        #expect(alternate.b == blue)
        #expect(look.fadeIn == 2)
        #expect(look.isValid(for: profile))
    }

    @Test("Une seule couleur : B est son opposé sur la roue, jamais la même")
    func monochromeToAlternate() throws {
        let look = try #require(colorsLook([red, red, red, red]).converted(to: .alternate, profile: profile))
        guard case .alternate(let alternate) = look.content else { Issue.record("pas une alternance"); return }
        #expect(alternate.a == red)
        #expect(alternate.b != alternate.a)
        #expect(alternate.b.hue == 180)
    }

    @Test("Alternance → couleurs : A sur 1 et 3, B sur 2 et 4")
    func alternateToColors() throws {
        let start = LightLook(content: .alternate(AlternateLook(a: red, b: blue, every: .bar, switchFade: 0, fallbackBPM: 100)))
        let look = try #require(start.converted(to: .colors, profile: profile))
        guard case .colors(let colors) = look.content else { Issue.record("pas des couleurs"); return }
        #expect(colors.heads.map(\.color) == [red, blue, red, blue])
        #expect(colors.linked == false)
        #expect(colors.strobe == nil)
    }

    @Test("Programme ou sur le son → couleurs : tout en blanc, jamais d'état invalide")
    func fixtureModesToColors() throws {
        let program = LightLook(fadeIn: 1, content: .fixtureProgram(number: 5, speed: 0.2))
        let colors = try #require(program.converted(to: .colors, profile: profile))
        #expect(colors.isValid(for: profile))
        #expect(colors.fadeIn == 1)
        let alternate = try #require(program.converted(to: .alternate, profile: profile))
        #expect(alternate.isValid(for: profile))
        for style in LightLook.Content.Style.allCases {
            #expect(try #require(program.converted(to: style, profile: profile)).isValid(for: profile))
        }
    }

    @Test("Même type : rien ne change")
    func sameKind() {
        let look = colorsLook([red, blue, red, blue])
        #expect(look.converted(to: .colors, profile: profile) == look)
    }

    @Test("Ensemble : les quatre prennent la couleur du projecteur choisi, allumés ou non comme avant")
    func linkedTakesSource() {
        var look = ColorsLook(
            heads: [red, blue, red, blue].map { HeadLook(isOn: true, color: $0, intensity: 0.5) }, linked: false, strobe: nil)
        look.heads[2].isOn = false
        let linked = look.settingLinked(true, source: 1)
        #expect(linked.linked)
        #expect(linked.heads.allSatisfy { $0.color == blue && $0.intensity == 0.5 })
        #expect(linked.heads.map(\.isOn) == [true, true, false, true])
        let back = linked.settingLinked(false)
        #expect(back.linked == false)
        #expect(back.heads == linked.heads)
    }

    @Test("isValid refuse un état d'un autre appareil")
    func invalidForProfile() {
        let tooFewHeads = LightLook.uniform(color: red, intensity: 1, headCount: 3)
        #expect(!tooFewHeads.isValid(for: profile))
        #expect(LightLook.uniform(color: red, intensity: 1, headCount: 4).isValid(for: profile))
        #expect(!LightLook(content: .fixtureProgram(number: 13, speed: 0.5)).isValid(for: profile))
    }
}
