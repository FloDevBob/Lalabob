import LalabobModel
import Testing

@testable import ControllerDrivers

/// Étalonnage des couleurs des LED RVB : les teintes de l'écran paraissent délavées sur un Launchpad sans correction.
@Suite("Étalonnage des LED")
struct LEDCalibrationTests {
    private let samples = Tint.allCases.map(\.spec.vivid) + [RGB(hex: 0x000000), RGB(hex: 0xFFFFFF), RGB(hex: 0x808080)]

    @Test("Neutre : la couleur est inchangée")
    func neutralIsIdentity() {
        for color in samples { #expect(LEDCalibration.neutral.apply(to: color) == color) }
    }

    @Test("Le noir reste noir et le blanc reste blanc, sans correction de luminosité")
    func blackAndWhite() {
        #expect(LEDCalibration.standard.apply(to: RGB(hex: 0x000000)) == RGB(hex: 0x000000))
        #expect(LEDCalibration.standard.apply(to: RGB(hex: 0xFFFFFF)) == RGB(hex: 0xFFFFFF))
    }

    @Test("Le gamma creuse les teintes moyennes : une couleur délavée devient plus profonde")
    func gammaDeepensColors() {
        let pale = RGB(hex: 0x34D399)  // vert menthe
        let result = LEDCalibration(saturation: 1, gamma: 2, brightness: 1).apply(to: pale)
        #expect(result.red < pale.red)
        #expect(result.blue < pale.blue)
        #expect(result.green < pale.green)
        // Le canal dominant garde l'avantage, et même davantage : plus de couleur, moins de blanc.
        let ratioBefore = Double(pale.green) / Double(pale.blue)
        let ratioAfter = Double(result.green) / Double(max(result.blue, 1))
        #expect(ratioAfter > ratioBefore)
    }

    @Test("La saturation écarte les canaux du gris")
    func saturationSeparatesChannels() {
        let color = RGB(hex: 0xA0C0B0)
        let boosted = LEDCalibration(saturation: 1.5, gamma: 1, brightness: 1).apply(to: color)
        let muted = LEDCalibration(saturation: 0.5, gamma: 1, brightness: 1).apply(to: color)
        func spread(_ c: RGB) -> Int { Int(max(c.red, c.green, c.blue)) - Int(min(c.red, c.green, c.blue)) }
        #expect(spread(boosted) > spread(color))
        #expect(spread(muted) < spread(color))
        // Un gris reste gris, quelle que soit la saturation.
        let gray = LEDCalibration(saturation: 2, gamma: 1, brightness: 1).apply(to: RGB(hex: 0x808080))
        #expect(gray == RGB(hex: 0x808080))
    }

    @Test("La luminosité est proportionnelle et bornée")
    func brightness() {
        let color = RGB(hex: 0x806040)
        let half = LEDCalibration(saturation: 1, gamma: 1, brightness: 0.5).apply(to: color)
        #expect(half == RGB(red: 64, green: 48, blue: 32))
        let over = LEDCalibration(saturation: 1, gamma: 1, brightness: 1.5).apply(to: RGB(hex: 0xFFC080))
        #expect(over.red == 255)
    }

    @Test("Des réglages hors plage ou invalides sont ramenés dans leurs bornes")
    func clamping() {
        let wild = LEDCalibration(saturation: .infinity, gamma: -3, brightness: .nan).clamped
        #expect(wild.saturation == 1)  // non fini : valeur neutre
        #expect(wild.gamma == LEDCalibration.gammaRange.lowerBound)
        #expect(wild.brightness == 1)
        let result = LEDCalibration(saturation: 99, gamma: 99, brightness: 99).apply(to: RGB(hex: 0x123456))
        _ = result  // ne plante pas
    }

    @Test("Chaque teinte reste distincte et lisible après étalonnage")
    func tintsStayDistinct() {
        let calibrated = Tint.allCases.map { LEDCalibration.standard.apply(to: $0.spec.vivid) }
        #expect(Set(calibrated).count == Tint.allCases.count)
    }

    @Test("Le Launchpad envoie la couleur étalonnée, puis l'intensité s'applique sur la commande de la LED")
    func launchpadUsesTheCalibration() {
        let position = GridPosition(column: 0, row: 7)
        let calibration = LEDCalibration(saturation: 1, gamma: 2, brightness: 1)
        let driver = LaunchpadDriver(model: .launchpadMiniMK3, calibration: calibration)

        func payload(_ intensity: LEDIntensity) -> [UInt8] {
            guard case .systemExclusive(let bytes)? = driver.ledMessages([position: .lit(.rouge, intensity)]).first else { return [] }
            return Array(bytes[bytes.count - 4..<bytes.count - 1])  // R G B avant F7
        }
        let expected = calibration.apply(to: Tint.rouge.spec.vivid)
        #expect(payload(.full) == [expected.red >> 1, expected.green >> 1, expected.blue >> 1])
        // 50 % = la moitié de la commande de la LED, pas la moitié de la couleur de l'écran.
        let half = expected.scaled(by: 0.5)
        #expect(payload(.half) == [half.red >> 1, half.green >> 1, half.blue >> 1])
    }

    @Test("Un pilote sans étalonnage envoie la couleur de l'écran telle quelle ; l'APC ne change pas")
    func defaultsAreTransparent() {
        let plain = LaunchpadDriver(model: .launchpadX)
        #expect(plain.calibration == .neutral)
        #expect(ControllerModel.launchpadMiniMK3.hasRGBLEDs)
        #expect(!ControllerModel.apcMiniMK2.hasRGBLEDs)
        let position = GridPosition(column: 1, row: 1)
        #expect(
            ControllerModel.apcMiniMK2.driver(calibration: .standard).ledMessages([position: .lit(.vert, .full)])
                == ControllerModel.apcMiniMK2.driver.ledMessages([position: .lit(.vert, .full)]))
    }
}
