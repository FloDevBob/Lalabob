import LalabobModel
import SwiftUI

extension Color {
    init(_ rgb: RGB) {
        self.init(.sRGB, red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }

    init(hex: UInt32) {
        self.init(RGB(hex: hex))
    }
}

extension Tint {
    /// Fond du pad.
    public var surfaceColor: Color { Color(spec.surface) }
    /// Texte du pad.
    public var labelColor: Color { Color(spec.label) }
    /// Couleur vive (états actifs).
    public var vividColor: Color { Color(spec.vivid) }
}

/// Couleurs d'interface de la maquette (mode sombre).
public enum Surface {
    public static let window = Color(hex: 0x0E0F12)
    public static let chrome = Color(hex: 0x121317)
    public static let panel = Color(hex: 0x15161B)
    public static let well = Color(hex: 0x0B0C0F)
    public static let textPrimary = Color(hex: 0xECEDF0)
    public static let textSecondary = Color(hex: 0xAEB2BB)
    public static let textTertiary = Color(hex: 0x8D919B)
    public static let emptyPadStroke = Color.white.opacity(0.11)
    public static let lightZone = Color(hex: 0xFFC93D).opacity(0.035)
    public static let lightAccent = Color(hex: 0xFFC93D)
}

/// Dimensions de la maquette.
public enum Metrics {
    public static let padCornerRadius: CGFloat = 14
    public static let padHeight: CGFloat = 56
    public static let padSpacing: CGFloat = 6
    public static let columnSpacing: CGFloat = 8
    public static let panelCornerRadius: CGFloat = 18
}

/// Typographie : SF Pro partout, Fredoka pour le logo (appeler `Fonts.register()` au lancement).
public enum Typography {
    public static let logo = Font.custom(Fonts.logoFamily, size: 23).weight(.semibold)
    public static let padTitle = Font.system(size: 13, weight: .semibold)
    public static let padSubtitle = Font.system(size: 11.5)
    public static let mono = Font.system(size: 11, design: .monospaced)
}
