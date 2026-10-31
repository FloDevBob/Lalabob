import Foundation
import Testing

@testable import LalabobModel

/// Contrastes WCAG des teintes : le texte d'un pad doit rester lisible sur son fond (AA = 4,5), y compris le
/// sous-titre (88 % d'opacité), et la couleur vive doit se détacher du fond de la fenêtre (3, éléments d'interface).
@Suite("Contrastes des teintes")
struct ContrastTests {
    private static let window = RGB(hex: 0x0E0F12)

    private static func luminance(_ color: RGB) -> Double {
        func linear(_ value: UInt8) -> Double {
            let v = Double(value) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    private static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    /// `foreground` à `opacity` posé sur `background`.
    private static func blended(_ foreground: RGB, over background: RGB, opacity: Double) -> RGB {
        func mix(_ f: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(f) * opacity + Double(b) * (1 - opacity)).rounded()) }
        return RGB(red: mix(foreground.red, background.red), green: mix(foreground.green, background.green), blue: mix(foreground.blue, background.blue))
    }

    @Test(arguments: Tint.allCases)
    func padTitleIsReadable(_ tint: Tint) {
        #expect(Self.contrast(tint.spec.label, tint.spec.surface) >= 4.5)
    }

    @Test(arguments: Tint.allCases)
    func padSubtitleIsReadable(_ tint: Tint) {
        let subtitle = Self.blended(tint.spec.label, over: tint.spec.surface, opacity: 0.88)
        #expect(Self.contrast(subtitle, tint.spec.surface) >= 4.5)
    }

    @Test(arguments: Tint.allCases)
    func vividColorStandsOutFromTheWindow(_ tint: Tint) {
        #expect(Self.contrast(tint.spec.vivid, Self.window) >= 3)
    }
}
