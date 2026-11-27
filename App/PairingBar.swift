import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Barre du bas pendant l'appairage lumière : le déroulé, la case cible et son état. Même hauteur que l'inspecteur,
/// pour que la grille ne bouge pas en entrant dans le mode.
struct PairingBar: View {
    @Environment(ShowController.self) private var controller

    var body: some View {
        let target = controller.selection.flatMap { controller.isLightCell($0) ? $0 : nil }
        let fader = controller.pairingFader
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Icon.spotlight.view(size: 17).foregroundStyle(Surface.lightAccent)
                Text("Relier aux projecteurs")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Surface.textPrimary)
                Spacer(minLength: 8)
                Button("Terminer") { controller.setPairingLights(false) }
                    .controlSize(.small)
                    .help("Terminer (fermer le cadenas termine aussi)")
            }
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 7) {
                    step("1", "Dans le logiciel des projecteurs (LightKey) : clic droit sur la lumière › External Control › Add Trigger…")
                    step("2", "Ici : appuyez sur un pad des colonnes lumière, ou cliquez son ampoule.")
                    step("3", "Pour une intensité : « Add Trigger… » sur le réglage dans LightKey, puis bougez le fader.")
                    step("4", "Quand les projecteurs répondent (ou sur « C'est relié »), nommez la lumière : la case suivante est prête.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                targetBox(target, fader: fader)
                    .frame(width: 300, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Metrics.inspectorHeight)
        .background(Surface.panel)
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .frame(width: 18, height: 18)
                .background(Surface.lightAccent.opacity(0.2), in: .circle)
                .foregroundStyle(Surface.lightAccent)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Surface.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func targetBox(_ target: GridPosition?, fader: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let fader {
                let paired = controller.isFaderPaired(column: fader)
                Text("Intensité de la colonne \(fader + 1)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Surface.textTertiary)
                if paired {
                    Text("Relié ✓")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Surface.loopAccent)
                    Button("Délier") { controller.unpairFader(column: fader) }
                        .controlSize(.small)
                        .help("Le réglage reste dans le logiciel des projecteurs ; seul Lalabob l'oublie")
                } else {
                    Text("Bougez le fader…")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Surface.lightAccent)
                    Button("C'est relié") { controller.confirmPairing() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help("Le logiciel des projecteurs ne répond pas toujours pour un fader : confirmez à la main")
                }
            } else if let target {
                let paired = controller.isPaired(at: target)
                Text("Colonne \(target.column + 1), ligne \(target.row + 1)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Surface.textTertiary)
                if paired {
                    Text("Reliée ✓")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Surface.loopAccent)
                    Button("Délier") { controller.unpairCue(at: target) }
                        .controlSize(.small)
                        .help("La lumière reste sur la grille ; rien ne change dans le logiciel des projecteurs")
                } else {
                    Text("En attente des projecteurs…")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Surface.lightAccent)
                    Button("C'est relié") { controller.confirmPairing() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help("Une lumière éteinte peut ne rien répondre : confirmez à la main")
                }
            } else {
                Text("Choisissez une case lumière (flèches du clavier ou clic).")
                    .font(.system(size: 12))
                    .foregroundStyle(Surface.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Surface.well, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}
