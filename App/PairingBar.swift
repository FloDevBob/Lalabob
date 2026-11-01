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
                Text("Appairage lumière")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Surface.textPrimary)
                Spacer(minLength: 8)
                Button("Terminer") { controller.setPairingLights(false) }
                    .controlSize(.small)
                    .help("Quitter l'appairage (le cadenas le quitte aussi)")
            }
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 7) {
                    step("1", "Dans LightKey : clic droit sur une cue › External Control › Add Trigger…")
                    step("2", "Appuyez sur un pad des deux colonnes de droite, ou cliquez son ampoule : la note part vers LightKey.")
                    step("3", "Pour un fader : « Add Trigger… » sur le réglage, puis bougez le fader (à la main ou à l'écran).")
                    step("4", "Quand LightKey répond (ou sur « C'est appairé »), c'est appairé : nommez la cue, la suivante s'arme.")
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
                let cc = controller.lightFaderCC(forColumn: fader).map { " · CC \($0)" } ?? ""
                Text("Fader de la colonne \(fader + 1)\(cc)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Surface.textTertiary)
                if paired {
                    Text("Appairé ✓")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Surface.loopAccent)
                    Button("Retirer l'appairage") { controller.unpairFader(column: fader) }
                        .controlSize(.small)
                        .help("Le réglage reste dans LightKey ; seul Lalabob l'oublie")
                } else {
                    Text("Bougez le fader…")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Surface.lightAccent)
                    Button("C'est appairé") { controller.confirmPairing() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help("LightKey ne répond pas toujours pour un fader : confirmez à la main")
                }
            } else if let target {
                let paired = controller.isPaired(at: target)
                Text("Colonne \(target.column + 1), ligne \(target.row + 1)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Surface.textTertiary)
                if paired {
                    Text("Appairée ✓")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Surface.loopAccent)
                    Button("Retirer l'appairage") { controller.unpairCue(at: target) }
                        .controlSize(.small)
                        .help("La cue reste sur la grille ; LightKey n'est pas modifié")
                } else {
                    Text("En attente de LightKey…")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Surface.lightAccent)
                    Button("C'est appairé") { controller.confirmPairing() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help("Une cue éteinte peut ne rien répondre : confirmez à la main")
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
