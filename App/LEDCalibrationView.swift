import ControllerDrivers
import LalabobDesign
import LalabobEngine
import SwiftUI

/// Étalonnage des couleurs des LED du Launchpad (popover de l'indicateur de contrôleur).
///
/// Les LED RVB d'un Launchpad rendent les teintes de l'écran délavées : on creuse les teintes (gamma), on les sature, on
/// règle la luminosité. Chaque mouvement est renvoyé tout de suite aux 64 LED : on règle en regardant le contrôleur.
struct LEDCalibrationView: View {
    let session: ControllerSession

    var body: some View {
        let calibration = session.ledCalibration
        VStack(alignment: .leading, spacing: 14) {
            Text("Étalonnage des LED")
                .font(.system(size: 14, weight: .bold))
            Text("Si les couleurs du Launchpad paraissent pâles, réglez-les en les comparant à l'écran. Les LED suivent chaque mouvement.")
                .font(.system(size: 12))
                .foregroundStyle(Surface.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            slider(
                "Saturation", value: calibration.saturation, range: LEDCalibration.saturationRange,
                hint: "Éloigne les couleurs du gris."
            ) { var c = calibration; c.saturation = $0; session.setLEDCalibration(c) }
            slider(
                "Profondeur (gamma)", value: calibration.gamma, range: LEDCalibration.gammaRange,
                hint: "Plus haut : couleurs plus profondes, moins de blanc."
            ) { var c = calibration; c.gamma = $0; session.setLEDCalibration(c) }
            slider(
                "Luminosité", value: calibration.brightness, range: LEDCalibration.brightnessRange,
                hint: "Intensité générale des LED."
            ) { var c = calibration; c.brightness = $0; session.setLEDCalibration(c) }

            HStack {
                Button("Réglage conseillé") { session.setLEDCalibration(.standard) }
                    .help("Saturation 1,2 · gamma 2,0 · luminosité 1,0")
                Button("Sans correction") { session.setLEDCalibration(.neutral) }
                    .help("La couleur de l'écran telle quelle (très pâle sur un Launchpad)")
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 320)
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
