import ControllerDrivers
import LalabobDesign
import LalabobEngine
import SwiftUI

/// Réglages de couleur des LED du contrôleur branché (popover de l'indicateur de contrôleur).
///
/// - **Launchpad** : LED RVB. Elles rendent les teintes de l'écran délavées : on creuse les teintes (gamma), on les
///   sature, on règle la luminosité.
/// - **APC mini mk2** : palette fixe d'Akai par défaut (rien à étalonner). Le mode **RVB libre** envoie les teintes de
///   l'écran en SysEx : mêmes réglages que le Launchpad. À valider sur le matériel : on peut revenir à la palette d'un clic.
///
/// Chaque mouvement est renvoyé tout de suite aux LED : on règle en regardant le contrôleur.
struct LEDCalibrationView: View {
    let session: ControllerSession
    let model: ControllerModel

    private var settings: LEDSettings { session.ledSettings(for: model) }
    private var canCalibrate: Bool { model.hasRGBLEDs || settings.usesRGB }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Couleurs des LED · \(model.displayName)")
                .font(.system(size: 14, weight: .bold))

            if model == .apcMiniMK2 {
                Picker(
                    "Couleurs",
                    selection: Binding(get: { settings.usesRGB }, set: { setRGB($0) })
                ) {
                    Text("Palette Akai").tag(false)
                    Text("RVB libre (essai)").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(
                    settings.usesRGB
                        ? "Les teintes de l'écran sont envoyées en RVB. Si les LED ne réagissent pas ou se comportent bizarrement, revenez à la palette Akai."
                        : "La palette d'Akai a 128 couleurs fixes : les teintes sont les plus proches. Passez en RVB libre pour les reproduire et les étalonner."
                )
                .font(.system(size: 12))
                .foregroundStyle(Surface.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Si les couleurs du Launchpad paraissent pâles, réglez-les en les comparant à l'écran. Les LED suivent chaque mouvement.")
                    .font(.system(size: 12))
                    .foregroundStyle(Surface.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if canCalibrate {
                slider(
                    "Saturation", value: settings.calibration.saturation, range: LEDCalibration.saturationRange,
                    hint: "Éloigne les couleurs du gris."
                ) { update { $0.calibration.saturation = $1 }($0) }
                slider(
                    "Profondeur (gamma)", value: settings.calibration.gamma, range: LEDCalibration.gammaRange,
                    hint: "Plus haut : couleurs plus profondes, moins de blanc."
                ) { update { $0.calibration.gamma = $1 }($0) }
                slider(
                    "Luminosité", value: settings.calibration.brightness, range: LEDCalibration.brightnessRange,
                    hint: "Intensité générale des LED."
                ) { update { $0.calibration.brightness = $1 }($0) }

                HStack {
                    Button("Réglage conseillé") { apply(.standard) }
                        .help("Saturation 1,2 · gamma 2,0 · luminosité 1,0")
                    Button("Sans correction") { apply(.neutral) }
                        .help("La couleur de l'écran telle quelle (très pâle sur un Launchpad)")
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 330)
    }

    private func setRGB(_ usesRGB: Bool) {
        var next = settings
        next.usesRGB = usesRGB
        session.setLEDSettings(next, for: model)
    }

    /// Remplace l'étalonnage en gardant le mode (palette / RVB).
    private func apply(_ calibration: LEDCalibration) {
        var next = settings
        next.calibration = calibration
        session.setLEDSettings(next, for: model)
    }

    /// Une fonction qui modifie une valeur de l'étalonnage actuel et l'envoie.
    private func update(_ change: @escaping (inout LEDSettings, Double) -> Void) -> (Double) -> Void {
        { value in
            var next = settings
            change(&next, value)
            session.setLEDSettings(next, for: model)
        }
    }

    private func slider(
        _ title: String, value: Double, range: ClosedRange<Double>, hint: String, onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .font(Typography.mono)
                    .foregroundStyle(Surface.textSecondary)
            }
            Slider(value: Binding(get: { value }, set: onChange), in: range)
                .accessibilityLabel(title)
            Text(hint).font(.system(size: 11)).foregroundStyle(Surface.textTertiary)
        }
    }
}
