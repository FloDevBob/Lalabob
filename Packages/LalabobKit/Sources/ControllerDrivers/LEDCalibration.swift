import Foundation
import LalabobModel

/// Étalonnage des couleurs pour un contrôleur à LED RVB (Launchpad).
///
/// Les teintes de l'app sont pensées pour un écran. Les LED d'un Launchpad sont très lumineuses et leurs canaux se
/// mélangent mal : envoyer la couleur de l'écran telle quelle donne des couleurs **délavées, presque pastel**. Trois
/// réglages, appliqués dans cet ordre à la couleur vive de la teinte :
/// 1. `saturation` : éloigne chaque canal du gris (1 = sans effet) ;
/// 2. `gamma` : creuse les teintes moyennes (1 = sans effet ; un Launchpad aime 1,8 à 2,4) ;
/// 3. `brightness` : luminosité globale (1 = sans effet).
///
/// L'intensité du pad (100 %, 50 %, 25 %, pastel) s'applique **ensuite**, sur la commande de la LED.
/// Pure et testable ; réglable depuis l'indicateur de contrôleur de l'en-tête.
public struct LEDCalibration: Codable, Equatable, Sendable {
    public var saturation: Double
    public var gamma: Double
    public var brightness: Double

    public static let saturationRange = 0.5...2.0
    public static let gammaRange = 1.0...3.0
    public static let brightnessRange = 0.3...1.5

    public init(saturation: Double, gamma: Double, brightness: Double) {
        self.saturation = saturation
        self.gamma = gamma
        self.brightness = brightness
    }

    /// Sans correction : la couleur de l'écran telle quelle.
    public static let neutral = LEDCalibration(saturation: 1, gamma: 1, brightness: 1)

    /// Point de départ pour un Launchpad : couleurs plus profondes et plus saturées (à affiner à l'œil).
    public static let standard = LEDCalibration(saturation: 1.2, gamma: 2.0, brightness: 1)

    /// Valeurs ramenées dans leurs plages (un fichier de réglages abîmé ne doit rien casser).
    public var clamped: LEDCalibration {
        func fit(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
        }
        return LEDCalibration(
            saturation: fit(saturation, Self.saturationRange, fallback: 1),
            gamma: fit(gamma, Self.gammaRange, fallback: 1),
            brightness: fit(brightness, Self.brightnessRange, fallback: 1))
    }

    /// La couleur de la LED à envoyer (0–255 par canal) pour cette couleur d'écran.
    public func apply(to color: RGB) -> RGB {
        let settings = clamped
        let channels = [Double(color.red), Double(color.green), Double(color.blue)].map { $0 / 255 }
        let luma = 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        let adjusted = channels.map { channel -> UInt8 in
            let saturated = min(max(luma + (channel - luma) * settings.saturation, 0), 1)
            let curved = pow(saturated, settings.gamma) * settings.brightness
            return UInt8((min(max(curved, 0), 1) * 255).rounded())
        }
        return RGB(red: adjusted[0], green: adjusted[1], blue: adjusted[2])
    }
}

/// Réglages de couleur d'un contrôleur : l'étalonnage, et pour l'APC mini mk2 le mode d'envoi des couleurs.
///
/// Un jeu de réglages par **famille** de contrôleur (`ControllerModel.ledFamily`) : les Launchpad partagent les leurs,
/// l'APC a les siens (ses LED ne rendent pas les couleurs comme celles d'un Launchpad).
public struct LEDSettings: Codable, Equatable, Sendable {
    public var calibration: LEDCalibration
    /// APC mini mk2 seulement : envoyer des couleurs **RVB libres** (SysEx) au lieu de la palette fixe d'Akai.
    /// Les teintes de l'écran sont alors reproduites et étalonnables comme sur un Launchpad. À valider sur le matériel ;
    /// désactivé par défaut. Sans effet sur un Launchpad (toujours en RVB).
    public var usesRGB: Bool

    public init(calibration: LEDCalibration, usesRGB: Bool = false) {
        self.calibration = calibration
        self.usesRGB = usesRGB
    }

    public static let standard = LEDSettings(calibration: .standard)
    public static let neutral = LEDSettings(calibration: .neutral)

    public var clamped: LEDSettings { LEDSettings(calibration: calibration.clamped, usesRGB: usesRGB) }
}
