import Testing

@testable import LalabobModel

@Suite("Libellé automatique d'un pad lumière")
struct LightLabelTests {
    func look(_ colors: [LightColor], on: [Bool]? = nil, intensity: Double = 1) -> LightLook {
        let heads = colors.enumerated().map { HeadLook(isOn: on?[$0.offset] ?? true, color: $0.element, intensity: intensity) }
        return LightLook(content: .colors(ColorsLook(heads: heads, linked: false, strobe: nil)))
    }

    @Test("Les couleurs franches : ambiance en titre, nom simple en sous-titre", arguments: [
        (0.0, 1.0, "Danger", "Rouge"), (30.0, 1.0, "Soir", "Orange"), (55.0, 1.0, "Soleil", "Jaune"),
        (120.0, 1.0, "Forêt", "Vert"), (180.0, 1.0, "Mer", "Turquoise"), (225.0, 1.0, "Nuit", "Bleu"),
        (270.0, 1.0, "Mystère", "Violet"), (320.0, 1.0, "Romantique", "Rose"),
    ])
    func hues(hue: Double, saturation: Double, mood: String, plain: String) {
        let label = look([LightColor(hue: hue, saturation: saturation)]).autoLabel
        #expect(label == LightLabel(title: mood, subtitle: plain))
    }

    @Test("Les blancs : neutre, chaud (vers l'orange), froid (vers le bleu)")
    func whites() {
        #expect(look([.white]).autoLabel == LightLabel(title: "Lumière du jour", subtitle: "Blanc"))
        #expect(look([LightColor(hue: 35, saturation: 0.25)]).autoLabel == LightLabel(title: "Lumière douce", subtitle: "Blanc chaud"))
        #expect(look([LightColor(hue: 215, saturation: 0.25)]).autoLabel == LightLabel(title: "Lumière froide", subtitle: "Blanc froid"))
    }

    @Test("Un pad tout éteint s'appelle Noir")
    func black() {
        #expect(look([.white, .white], on: [false, false]).autoLabel == LightLabel(title: "Noir", subtitle: "Tout éteint"))
        #expect(look([.white], intensity: 0).autoLabel.title == "Noir")
    }

    @Test("Les projecteurs éteints ne comptent pas ; des couleurs différentes : « Plusieurs couleurs »")
    func severalColors() {
        let red = LightColor(hue: 0, saturation: 1), blue = LightColor(hue: 225, saturation: 1)
        #expect(look([red, blue, red, blue], on: [true, false, true, false]).autoLabel == LightLabel(title: "Danger", subtitle: "Rouge"))
        #expect(look([red, blue]).autoLabel == LightLabel(title: "Plusieurs couleurs", subtitle: "Rouge et Bleu"))
        let green = LightColor(hue: 120, saturation: 1)
        #expect(look([red, blue, green]).autoLabel.subtitle == "Rouge et Bleu…")
    }

    @Test("Alternance, programme de la barre et « sur le son »")
    func effects() {
        let red = LightColor(hue: 0, saturation: 1), blue = LightColor(hue: 225, saturation: 1)
        let alternate = AlternateLook(a: red, b: blue, every: .beat, switchFade: 0, fallbackBPM: 120)
        #expect(LightLook(content: .alternate(alternate)).autoLabel == LightLabel(title: "Alternance", subtitle: "Rouge et Bleu"))
        #expect(LightLook(content: .fixtureProgram(number: 3, speed: 0.5)).autoLabel == LightLabel(title: "Programme 3", subtitle: "Programme de la barre"))
        #expect(LightLook(content: .soundActive(sensitivity: 0.5)).autoLabel == LightLabel(title: "Au rythme du son", subtitle: "Micro de la barre"))
    }
}
