import Testing

@testable import LalabobModel

@Suite("Résumé d'un état lumineux")
struct LightLookSummaryTests {
    let red = LightColor(hue: 0, saturation: 1)
    let blue = LightColor(hue: 240, saturation: 1)

    func colors(on: Set<Int>, linked: Bool, strobe: Double? = nil, intensity: Double = 1) -> LightLook {
        let heads = (0..<4).map { HeadLook(isOn: on.contains($0), color: red, intensity: intensity) }
        return LightLook(content: .colors(ColorsLook(heads: heads, linked: linked, strobe: strobe)))
    }

    @Test("Ensemble : les projecteurs allumés sont nommés")
    func linked() {
        #expect(colors(on: [1, 2], linked: true).summary.subtitle == "Ensemble · 2 et 3")
        #expect(colors(on: [0, 1, 2, 3], linked: true).summary.subtitle == "Ensemble · les 4")
        #expect(colors(on: [2], linked: true).summary.subtitle == "Ensemble · 3")
    }

    @Test("Chacun, avec trois projecteurs et du strobo")
    func eachAndStrobe() {
        let summary = colors(on: [0, 1, 3], linked: false, strobe: 0.5).summary
        #expect(summary.subtitle == "Chacun · 1, 2 et 4 · Strobo")
        #expect(summary.hasStrobe)
        #expect(summary.dots.map(\.isOn) == [true, true, false, true])
    }

    @Test("Tout éteint, ou intensité à zéro : « Éteint », points gris")
    func black() {
        #expect(colors(on: [], linked: true).summary.subtitle == "Éteint")
        let zero = colors(on: [0, 1], linked: true, intensity: 0).summary
        #expect(zero.subtitle == "Éteint")
        #expect(zero.dots.allSatisfy { !$0.isOn })
    }

    @Test("Un strobo à zéro n'est pas un strobo")
    func zeroStrobe() {
        #expect(!colors(on: [0], linked: true, strobe: 0).summary.hasStrobe)
        #expect(!colors(on: [0], linked: true, strobe: nil).summary.hasStrobe)
    }

    @Test("Alternance : A sur 1 et 3, B sur 2 et 4")
    func alternate() {
        let look = LightLook(
            content: .alternate(AlternateLook(a: red, b: blue, every: .beat, switchFade: 0.1, fallbackBPM: 123.6)))
        let summary = look.summary
        #expect(summary.dots.map(\.color) == [red, blue, red, blue])
        #expect(summary.subtitle == "⇄ 124 BPM · son en cours")
        #expect(summary.kind == .alternate)
    }

    @Test("Programme et sur le son : pas de points, la barre choisit")
    func fixtureModes() {
        let program = LightLook(content: .fixtureProgram(number: 3, speed: 0.4)).summary
        #expect(program.dots.isEmpty)
        #expect(program.kind == .program(number: 3))
        #expect(program.subtitle == "Programme 3 · 40 %")
        let sound = LightLook(content: .soundActive(sensitivity: 0.6)).summary
        #expect(sound.kind == .sound)
        #expect(sound.subtitle == "Sur le son · 60 %")
    }
}
