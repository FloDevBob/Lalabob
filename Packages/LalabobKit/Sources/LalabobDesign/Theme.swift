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
    /// Boucle activée (bouton de transport).
    public static let loopAccent = Color(hex: 0x3DDC6E)
}

/// Dimensions de la maquette.
public enum Metrics {
    public static let padCornerRadius: CGFloat = 14
    public static let padHeight: CGFloat = 56
    public static let padSpacing: CGFloat = 6
    public static let columnSpacing: CGFloat = 8
    public static let panelCornerRadius: CGFloat = 18
    /// Hauteur maximale de l'inspecteur (panneau du bas) : environ 1/5 d'une fenêtre de régie.
    public static let inspectorHeight: CGFloat = 196
}

/// Typographie : SF Pro partout, Fredoka pour le logo (appeler `Fonts.register()` au lancement).
public enum Typography {
    public static let logo = Font.custom(Fonts.logoFamily, size: 23).weight(.semibold)
    public static let padTitle = Font.system(size: 13, weight: .semibold)
    public static let padSubtitle = Font.system(size: 11.5)
    public static let mono = Font.system(size: 11, design: .monospaced)
}

/// Hauteurs de la grille qui s'adaptent à la fenêtre. Les **pads** absorbent toute la hauteur disponible : plus hauts
/// quand la fenêtre l'est (jusqu'à `maximumPadHeight`), plus bas quand elle l'est moins. La **piste des faders** garde
/// sa taille (120 pt) ; elle ne rétrécit qu'en dernier recours, quand les pads ont atteint leur minimum lisible
/// (petite fenêtre, plein écran d'un portable). Sous ce minimum, la zone défile. Pure, donc testable.
public struct GridDensity: Equatable, Sendable {
    public var padHeight: CGFloat
    public var faderTrackHeight: CGFloat

    public init(padHeight: CGFloat, faderTrackHeight: CGFloat) {
        self.padHeight = padHeight
        self.faderTrackHeight = faderTrackHeight
    }

    /// Les dimensions de la maquette (valeur par défaut avant la mesure de la fenêtre).
    public static let regular = GridDensity(padHeight: Metrics.padHeight, faderTrackHeight: 120)

    /// En dessous, le titre et le sous-titre d'un pad ne tiennent plus.
    public static let minimumPadHeight: CGFloat = 38
    /// Au-delà, un pad devient une grande dalle sans intérêt de plus.
    public static let maximumPadHeight: CGFloat = 110
    public static let minimumFaderTrackHeight: CGFloat = 64

    /// Hauteur de tout ce qui n'est ni pad ni piste de fader : en-tête de colonne, espaces, carte de volume (marges,
    /// valeur), marges de la grille.
    public static let fixedHeight: CGFloat = 152

    /// Densité qui tient dans `availableHeight` (la zone de la grille, sans l'en-tête de la fenêtre ni la barre du bas).
    public static func fitting(availableHeight: CGFloat) -> GridDensity {
        guard availableHeight.isFinite else { return .regular }
        let rows = CGFloat(8)
        let track = regular.faderTrackHeight
        let free = availableHeight - fixedHeight

        // Cas courant : la piste garde sa taille, les pads prennent le reste.
        let pad = (free - track) / rows
        if pad >= minimumPadHeight {
            return GridDensity(padHeight: min(pad, maximumPadHeight), faderTrackHeight: track)
        }
        // Fenêtre basse : pads au minimum, la piste cède ce qu'il faut (jusqu'à son propre minimum).
        let shrunkTrack = min(max(free - rows * minimumPadHeight, minimumFaderTrackHeight), track)
        return GridDensity(padHeight: minimumPadHeight, faderTrackHeight: shrunkTrack)
    }
}

extension EnvironmentValues {
    /// Hauteurs de la grille adaptées à la fenêtre (posées par la fenêtre principale).
    @Entry public var gridDensity = GridDensity.regular
}

/// Mouvements de l'interface : courts, utiles (ils expliquent un changement), jamais décoratifs. Les vumètres, les
/// faders et tout ce qui doit réagir tout de suite à la main ne sont pas animés. « Réduire les animations » les coupe.
public enum Motion {
    /// Ouverture et fermeture d'un panneau (bibliothèque à gauche, barre du bas).
    public static let panel = Animation.smooth(duration: 0.28)
    /// Changement de grille : la page des pads défile (vers le bas en avançant dans les onglets, vers le haut en reculant).
    public static let pageScroll = Animation.smooth(duration: 0.42)
}
