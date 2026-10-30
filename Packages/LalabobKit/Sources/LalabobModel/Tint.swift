/// Couleur sRGB 8 bits par canal, sans dépendance à SwiftUI ou AppKit.
public struct RGB: Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `RGB(hex: 0xFF5C66)`
    public init(hex: UInt32) {
        self.init(
            red: UInt8((hex >> 16) & 0xFF),
            green: UInt8((hex >> 8) & 0xFF),
            blue: UInt8(hex & 0xFF)
        )
    }

    /// Mélange linéaire vers `other` (`amount` entre 0 et 1).
    public func mixed(with other: RGB, amount: Double) -> RGB {
        let t = min(max(amount, 0), 1)
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8((Double(a) + (Double(b) - Double(a)) * t).rounded())
        }
        return RGB(red: mix(red, other.red), green: mix(green, other.green), blue: mix(blue, other.blue))
    }

    /// Multiplie la luminosité (`factor` entre 0 et 1).
    public func scaled(by factor: Double) -> RGB {
        mixed(with: RGB(red: 0, green: 0, blue: 0), amount: 1 - factor)
    }

    public static let white = RGB(red: 255, green: 255, blue: 255)
}

/// Les 16 teintes de Lalabob (maquette, planche « Palette »).
///
/// Un pad stocke une teinte, jamais un code couleur : l'écran et chaque contrôleur
/// la traduisent à leur manière.
public enum Tint: String, Codable, CaseIterable, Sendable {
    case rouge, orange, ambre, lime, vert, menthe, lagon, turquoise
    case ciel, azur, indigo, violet, fuchsia, rose, blanc, graphite

    public var displayName: String {
        switch self {
        case .rouge: "Rouge"
        case .orange: "Orange"
        case .ambre: "Ambre"
        case .lime: "Lime"
        case .vert: "Vert"
        case .menthe: "Menthe"
        case .lagon: "Lagon"
        case .turquoise: "Turquoise"
        case .ciel: "Ciel"
        case .azur: "Azur"
        case .indigo: "Indigo"
        case .violet: "Violet"
        case .fuchsia: "Fuchsia"
        case .rose: "Rose"
        case .blanc: "Blanc"
        case .graphite: "Graphite"
        }
    }

    public var spec: TintSpec { TintSpec.table[self]! }
}

/// Les valeurs d'une teinte.
public struct TintSpec: Sendable, Equatable {
    /// Fond du pad à l'écran (mode sombre).
    public let surface: RGB
    /// Texte du pad : déclinaison très claire de la teinte.
    public let label: RGB
    /// Couleur vive : LED du contrôleur et états actifs à l'écran.
    public let vivid: RGB
    /// Entrée de palette (vélocité) la plus proche, pour les contrôleurs sans RVB libre.
    /// À vérifier sur le matériel (voir docs/hardware).
    public let paletteVelocity: UInt8

    static let table: [Tint: TintSpec] = [
        .rouge: .init(surface: .init(hex: 0x8C2B32), label: .init(hex: 0xFFE1E2), vivid: .init(hex: 0xFF5C66), paletteVelocity: 5),
        .orange: .init(surface: .init(hex: 0x8F4317), label: .init(hex: 0xFFE6D4), vivid: .init(hex: 0xFF8A3D), paletteVelocity: 9),
        .ambre: .init(surface: .init(hex: 0x755A0E), label: .init(hex: 0xFFF2C7), vivid: .init(hex: 0xFFC93D), paletteVelocity: 13),
        .lime: .init(surface: .init(hex: 0x4E6416), label: .init(hex: 0xEEFAC8), vivid: .init(hex: 0xB4E33D), paletteVelocity: 17),
        .vert: .init(surface: .init(hex: 0x1E6A36), label: .init(hex: 0xD7F7DF), vivid: .init(hex: 0x3DDC6E), paletteVelocity: 21),
        .menthe: .init(surface: .init(hex: 0x0F6650), label: .init(hex: 0xD2F7EA), vivid: .init(hex: 0x34D9A0), paletteVelocity: 25),
        .lagon: .init(surface: .init(hex: 0x0C625E), label: .init(hex: 0xCFF5F1), vivid: .init(hex: 0x2CCFC0), paletteVelocity: 29),
        .turquoise: .init(surface: .init(hex: 0x0C5B6E), label: .init(hex: 0xCFF1F7), vivid: .init(hex: 0x2BC4E0), paletteVelocity: 33),
        .ciel: .init(surface: .init(hex: 0x105386), label: .init(hex: 0xD6EBFF), vivid: .init(hex: 0x45A8FF), paletteVelocity: 37),
        .azur: .init(surface: .init(hex: 0x22479E), label: .init(hex: 0xDCE5FF), vivid: .init(hex: 0x5B8CFF), paletteVelocity: 41),
        .indigo: .init(surface: .init(hex: 0x3A3BA6), label: .init(hex: 0xE0E0FF), vivid: .init(hex: 0x7B7BFF), paletteVelocity: 45),
        .violet: .init(surface: .init(hex: 0x5530A0), label: .init(hex: 0xE8DEFF), vivid: .init(hex: 0xA57CFF), paletteVelocity: 49),
        .fuchsia: .init(surface: .init(hex: 0x77268C), label: .init(hex: 0xF6DDFF), vivid: .init(hex: 0xD45CF5), paletteVelocity: 53),
        .rose: .init(surface: .init(hex: 0x8C2558), label: .init(hex: 0xFFDDEB), vivid: .init(hex: 0xFF5CA8), paletteVelocity: 57),
        .blanc: .init(surface: .init(hex: 0x4A4D55), label: .init(hex: 0xF4F5F7), vivid: .init(hex: 0xF4F5F7), paletteVelocity: 3),
        .graphite: .init(surface: .init(hex: 0x30333A), label: .init(hex: 0xD3D6DD), vivid: .init(hex: 0x9A9EA8), paletteVelocity: 1),
    ]
}

/// Intensité de la LED d'un pad.
public enum LEDIntensity: String, Codable, CaseIterable, Sendable {
    case pastel, full, half, quarter

    public var displayName: String {
        switch self {
        case .pastel: "Pastel"
        case .full: "100 %"
        case .half: "50 %"
        case .quarter: "25 %"
        }
    }

    /// Couleur LED d'une teinte à cette intensité.
    public func apply(to color: RGB) -> RGB {
        switch self {
        case .full: color
        case .pastel: color.mixed(with: .white, amount: 0.45)
        case .half: color.scaled(by: 0.5)
        case .quarter: color.scaled(by: 0.25)
        }
    }
}
