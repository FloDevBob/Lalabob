import Foundation
import LalabobDMX
import LalabobModel
import Testing

@testable import LalabobEngine

/// Console lumière (J14, étape 3) : un état → une trame, à un instant donné. Tout se calcule sur des valeurs : on lit
/// les trames à t = 0, à mi-fondu et à la fin, sans boîtier ni horloge réelle.
@Suite("Console lumière DMX")
struct LightConsoleTests {
    static let red = LightColor(hue: 0, saturation: 1)
    static let green = LightColor(hue: 120, saturation: 1)
    static let blue = LightColor(hue: 240, saturation: 1)
    let profile = FixtureProfile.chauvet4BarLTBT
    let padA = UUID()
    let padB = UUID()

    func console(address: Int = 1, blackoutFade: Double = 1.5) -> LightConsole {
        LightConsole(rig: DMXRig(address: address, blackoutFade: blackoutFade))
    }

    func uniform(_ color: LightColor, intensity: Double = 1, fadeIn: Double = 0) -> LightLook {
        var look = LightLook.uniform(color: color, intensity: intensity, headCount: 4)
        look.fadeIn = fadeIn
        return look
    }

    /// Rouge / vert / bleu du projecteur `head` (1…4) pour une barre à l'adresse 1.
    func rgb(_ frame: DMXFrame, head: Int, address: Int = 1) -> [UInt8] {
        let first = address + 3 + (head - 1) * 3
        return [frame[first], frame[first + 1], frame[first + 2]]
    }

    // MARK: - Repos et adresse

    @Test("Au départ, la barre est noire en pilotage direct, gradateur au général")
    func startsBlack() {
        let c = console()
        let frame = c.frame(at: 0)
        #expect(c.isBlack)
        #expect(c.activePad == nil)
        #expect(frame[1] == profile.directValue)
        #expect(frame[2] == 255)
        #expect(frame[3] == 0)
        for head in 1...4 { #expect(rgb(frame, head: head) == [0, 0, 0]) }
    }

    @Test("Les 15 canaux sont posés à l'adresse de la barre")
    func address() {
        var c = console(address: 50)
        c.play(uniform(Self.red), pad: padA, at: 0)
        let frame = c.frame(at: 1)
        #expect(frame.length >= 64)
        #expect(frame[1] == 0)
        #expect(frame[51] == 255)
        #expect(rgb(frame, head: 1, address: 50) == [255, 0, 0])
        #expect(rgb(frame, head: 4, address: 50) == [255, 0, 0])
    }

    // MARK: - Fondus

    @Test("Fondu d'entrée : noir à t = 0, moitié à mi-fondu, couleur pleine à la fin")
    func fadeIn() {
        var c = console()
        c.play(uniform(Self.red, fadeIn: 1), pad: padA, at: 10)
        #expect(c.activePad == padA)
        #expect(rgb(c.frame(at: 10), head: 1) == [0, 0, 0])
        #expect(rgb(c.frame(at: 10.5), head: 1) == [128, 0, 0])
        #expect(rgb(c.frame(at: 11), head: 1) == [255, 0, 0])
        #expect(rgb(c.frame(at: 60), head: 3) == [255, 0, 0])
    }

    @Test("Fondu enchaîné d'un état à l'autre")
    func crossfade() {
        var c = console()
        c.play(uniform(Self.red), pad: padA, at: 0)
        c.play(uniform(Self.blue, fadeIn: 2), pad: padB, at: 5)
        #expect(c.activePad == padB)
        #expect(rgb(c.frame(at: 5), head: 2) == [255, 0, 0])
        #expect(rgb(c.frame(at: 6), head: 2) == [128, 0, 128])
        #expect(rgb(c.frame(at: 7), head: 2) == [0, 0, 255])
    }

    @Test("Un nouvel appui pendant un fondu repart de la lumière en cours, sans saut")
    func interruptedFade() {
        var c = console()
        c.play(uniform(Self.red, fadeIn: 2), pad: padA, at: 0)
        c.play(uniform(Self.blue, fadeIn: 2), pad: padB, at: 1)  // le rouge est à moitié
        #expect(rgb(c.frame(at: 1), head: 1) == [128, 0, 0])
        #expect(rgb(c.frame(at: 2), head: 1) == [64, 0, 128])
        #expect(rgb(c.frame(at: 3), head: 1) == [0, 0, 255])
    }

    @Test("Intensité d'un projecteur et projecteur éteint dans l'état")
    func headIntensityAndOff() {
        var look = uniform(Self.green)
        guard case .colors(var colors) = look.content else { Issue.record("état couleurs attendu"); return }
        colors.heads[1].intensity = 0.5
        colors.heads[2].isOn = false
        colors.linked = false
        look.content = .colors(colors)
        var c = console()
        c.play(look, pad: padA, at: 0)
        let frame = c.frame(at: 0)
        #expect(rgb(frame, head: 1) == [0, 255, 0])
        #expect(rgb(frame, head: 2) == [0, 128, 0])
        #expect(rgb(frame, head: 3) == [0, 0, 0])
    }

    // MARK: - Noir

    @Test("Noir : fondu de la durée réglée, puis plus aucun pad actif")
    func blackout() {
        var c = console(blackoutFade: 1.5)
        c.play(uniform(Self.red), pad: padA, at: 0)
        c.blackout(at: 5)
        #expect(c.isBlack)
        #expect(c.activePad == nil)
        #expect(rgb(c.frame(at: 5), head: 1) == [255, 0, 0])
        #expect(rgb(c.frame(at: 5.75), head: 1) == [128, 0, 0])
        #expect(rgb(c.frame(at: 6.5), head: 1) == [0, 0, 0])
    }

    @Test("Noir pendant un programme de la barre : le programme reste, le gradateur descend, puis pilotage direct")
    func blackoutDuringProgram() {
        var c = console(blackoutFade: 1)
        c.play(LightLook(fadeIn: 0, content: .fixtureProgram(number: 3, speed: 0.5)), pad: padA, at: 0)
        c.blackout(at: 2)
        let program = profile.programValue(number: 3)!
        #expect(c.frame(at: 2.5)[1] == program)
        #expect(c.frame(at: 2.5)[2] == 128)
        #expect(c.frame(at: 3)[1] == profile.directValue)
        #expect(c.frame(at: 3)[3] == 0)
        for head in 1...4 { #expect(rgb(c.frame(at: 3), head: head) == [0, 0, 0]) }
    }

    @Test("Le général règle le gradateur, sans toucher aux couleurs")
    func master() {
        var c = console()
        c.master = 0.5
        c.play(uniform(Self.red), pad: padA, at: 0)
        #expect(c.frame(at: 0)[2] == 128)
        #expect(rgb(c.frame(at: 0), head: 1) == [255, 0, 0])
        c.master = 7  // borné
        #expect(c.frame(at: 0)[2] == 255)
    }

    // MARK: - Strobo, programmes, son

    @Test("Strobo : celui de l'état, sinon aucun ; le réglage direct passe devant")
    func strobe() {
        var look = uniform(Self.red)
        guard case .colors(var colors) = look.content else { return }
        colors.strobe = 1
        look.content = .colors(colors)
        var c = console()
        c.play(look, pad: padA, at: 0)
        #expect(c.frame(at: 0)[3] == profile.strobeFastest)
        c.play(uniform(Self.red), pad: padB, at: 1)
        #expect(c.frame(at: 1)[3] == 0)
        c.strobeOverride = 0.5
        #expect(c.frame(at: 1)[3] == profile.strobeValue(speed: 0.5))
    }

    @Test("Programme de la barre : canal programme, vitesse au canal 3, couleurs à zéro, sans attendre le fondu")
    func fixtureProgram() {
        var c = console()
        c.play(uniform(Self.red), pad: padA, at: 0)
        c.play(LightLook(fadeIn: 2, content: .fixtureProgram(number: 3, speed: 0.5)), pad: padB, at: 1)
        let frame = c.frame(at: 1)
        #expect(frame[1] == profile.programValue(number: 3))
        #expect(frame[3] == 128)
        #expect(frame[2] == 255)
    }

    @Test("Sur le son : valeur « son » de la barre et sensibilité 11…255")
    func soundActive() {
        var c = console()
        c.play(LightLook(fadeIn: 0, content: .soundActive(sensitivity: 0)), pad: padA, at: 0)
        #expect(c.frame(at: 0)[1] == 250)
        #expect(c.frame(at: 0)[3] == 11)
        c.play(LightLook(fadeIn: 0, content: .soundActive(sensitivity: 1)), pad: padA, at: 1)
        #expect(c.frame(at: 1)[3] == 255)
    }

    @Test("D'un programme vers des couleurs : pilotage direct tout de suite, couleurs qui montent du noir")
    func programToColors() {
        var c = console()
        c.play(LightLook(fadeIn: 0, content: .fixtureProgram(number: 1, speed: 0)), pad: padA, at: 0)
        c.play(uniform(Self.red, fadeIn: 1), pad: padB, at: 1)
        #expect(c.frame(at: 1)[1] == profile.directValue)
        #expect(rgb(c.frame(at: 1.5), head: 1) == [128, 0, 0])
    }

    // MARK: - Alternance

    func alternate(every: AlternateLook.Interval = .beat, switchFade: Double = 0) -> LightLook {
        LightLook(
            fadeIn: 0,
            content: .alternate(AlternateLook(a: Self.red, b: Self.blue, every: every, switchFade: switchFade, fallbackBPM: 120)))
    }

    @Test("Alternance : 1 et 3 en A, 2 et 4 en B, puis on échange à chaque temps (tempo de repli)")
    func alternateSwaps() {
        var c = console()
        c.play(alternate(), pad: padA, at: 0)
        let first = c.frame(at: 0.1)
        #expect(rgb(first, head: 1) == [255, 0, 0])
        #expect(rgb(first, head: 2) == [0, 0, 255])
        #expect(rgb(first, head: 3) == [255, 0, 0])
        #expect(rgb(first, head: 4) == [0, 0, 255])
        let second = c.frame(at: 0.6)  // 120 BPM : un temps = 0,5 s
        #expect(rgb(second, head: 1) == [0, 0, 255])
        #expect(rgb(second, head: 2) == [255, 0, 0])
        #expect(rgb(c.frame(at: 1.1), head: 1) == [255, 0, 0])
    }

    @Test("Alternance : fondu à la bascule")
    func alternateSwitchFade() {
        var c = console()
        c.play(alternate(switchFade: 0.1), pad: padA, at: 0)
        #expect(rgb(c.frame(at: 0.56), head: 1) == [102, 0, 153])  // 60 % de la bascule
        #expect(rgb(c.frame(at: 0.65), head: 1) == [0, 0, 255])
    }

    @Test("Alternance : une mesure = 4 temps ; le tempo du son passe devant le tempo de repli")
    func alternateIntervalAndTempo() {
        var c = console()
        c.play(alternate(every: .bar), pad: padA, at: 0)
        #expect(rgb(c.frame(at: 1.9), head: 1) == [255, 0, 0])
        #expect(rgb(c.frame(at: 2.1), head: 1) == [0, 0, 255])
        c.tempoBPM = 60
        c.play(alternate(), pad: padA, at: 10)
        #expect(rgb(c.frame(at: 10.6), head: 1) == [255, 0, 0])
        #expect(rgb(c.frame(at: 11.1), head: 1) == [0, 0, 255])
    }

    // MARK: - Couleurs et projecteurs en direct

    @Test("Fader Couleurs relatif : sa position au départ d'un état = couleurs du pad ; le bouger fait tourner la roue")
    func colorFaderRelative() {
        var c = console()
        c.colorFader = 0.5
        c.play(uniform(Self.red), pad: padA, at: 0)
        #expect(rgb(c.frame(at: 0), head: 1) == [255, 0, 0])  // quelle que soit sa position : l'origine
        c.colorFader = 0.5 + 1.0 / 3  // un tiers de course = 120°
        #expect(rgb(c.frame(at: 0), head: 1) == [0, 255, 0])
        c.colorFader = 0.5 - 1.0 / 3  // dans l'autre sens
        #expect(rgb(c.frame(at: 0), head: 1) == [0, 0, 255])
        // Un nouvel état repart de la position en cours.
        c.play(uniform(Self.red), pad: padB, at: 1)
        #expect(rgb(c.frame(at: 1), head: 1) == [255, 0, 0])
        c.play(uniform(.white), pad: padA, at: 2)
        c.colorFader = 0
        #expect(rgb(c.frame(at: 2), head: 1) == [255, 255, 255])  // le blanc reste blanc
    }

    @Test("Projecteur éteint à la main : en fondu, sans toucher aux autres ni au pad actif")
    func headToggle() {
        var c = console()
        c.play(uniform(Self.red), pad: padA, at: 0)
        c.setHead(1, on: false, at: 1)  // projecteur 2 (depuis 0)
        #expect(!c.isHeadOn(1))
        #expect(c.isHeadOn(0))
        #expect(rgb(c.frame(at: 1 + LightConsole.headFade / 2), head: 2) == [128, 0, 0])
        #expect(rgb(c.frame(at: 1 + LightConsole.headFade), head: 2) == [0, 0, 0])
        #expect(rgb(c.frame(at: 5), head: 1) == [255, 0, 0])
        #expect(c.activePad == padA)
        c.setHead(1, on: true, at: 5)
        #expect(rgb(c.frame(at: 5 + LightConsole.headFade), head: 2) == [255, 0, 0])
    }

    @Test("Couleurs vues par l'écran (mini-barre) : celles de la trame, gradateur compris")
    func headColorsForScreen() {
        var c = console()
        c.master = 0.5
        c.play(uniform(Self.red), pad: padA, at: 0)
        #expect(c.headColors(at: 0).count == 4)
        #expect(c.headColors(at: 0)[0] == RGB(red: 128, green: 0, blue: 0))
    }
}
