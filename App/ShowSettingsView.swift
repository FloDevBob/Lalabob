import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Réglages du spectacle (menu Spectacle › Réglages du spectacle…, déverrouillé) : pour l'instant, l'option
/// « Colonnes lumière communes à toutes les grilles » (fiche 01b) et son canal LightKey.
struct ShowSettingsView: View {
    @Environment(ShowController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    /// Activation en attente de confirmation (elle met des colonnes de côté dans les autres grilles).
    @State private var confirmsActivation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Réglages du spectacle")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(get: { controller.show.sharedLight != nil }, set: toggle)) {
                    Text("Mêmes lumières sur toutes les grilles")
                        .font(.body.weight(.medium))
                }
                .toggleStyle(.switch)
                .disabled(controller.isLocked || (controller.show.sharedLight == nil && activationProblem != nil))

                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(Surface.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if controller.show.sharedLight == nil, let activationProblem {
                    Text(activationProblem)
                        .font(.callout)
                        .foregroundStyle(Surface.lightAccent)
                }
            }

            if let sharedLight = controller.show.sharedLight {
                Picker("Canal des lumières communes", selection: Binding(
                    get: { sharedLight.channel },
                    set: { controller.setSharedLightChannel($0) }
                )) {
                    ForEach(Array(Show.lightChannels), id: \.self) { channel in
                        let owner = controller.gridIndex(usingLightChannel: channel)
                        Text(owner.map { "Canal \(channel) — \(controller.show.grids[$0].name)" } ?? "Canal \(channel)")
                            .tag(channel)
                            .selectionDisabled(owner != nil)
                    }
                }
                .disabled(controller.isLocked)
                Text("Changer ce canal oblige à relier de nouveau les lumières et intensités communes aux projecteurs.")
                    .font(.callout)
                    .foregroundStyle(Surface.textSecondary)
            }

            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .alert("Mêmes lumières sur toutes les grilles ?", isPresented: $confirmsActivation) {
            Button("Activer") { controller.setSharedLight(true) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(activationMessage)
        }
    }

    private var activationProblem: String? {
        controller.show.sharedLightActivationProblem(fromGrid: controller.selectedGridIndex)
    }

    private var explanation: String {
        if controller.show.sharedLight != nil {
            return "Les colonnes lumière sont les mêmes dans toutes les grilles : "
                + "changer de grille ne change pas la lumière. Désactiver rend à chaque grille les colonnes mises de côté ; "
                + "la grille « \(originName) » garde les colonnes communes."
        }
        return "Activée, les colonnes lumière de la grille affichée (« \(controller.currentGrid.name) ») deviennent communes à "
            + "toutes les grilles : on les relie aux projecteurs une seule fois. Les colonnes des autres grilles sont mises de côté et "
            + "reviennent si vous désactivez l'option."
    }

    private var originName: String {
        guard let id = controller.show.sharedLight?.originGridID else { return "" }
        return controller.show.grids.first { $0.id == id }?.name ?? ""
    }

    /// Ce qui sera mis de côté, grille par grille.
    private var activationMessage: String {
        let parking = controller.show.sharedLightParkingPreview(fromGrid: controller.selectedGridIndex)
        guard !parking.isEmpty else { return "Rien n'est mis de côté dans les autres grilles." }
        let lines = parking.map { item -> String in
            let name = controller.show.grids[item.grid].name
            let columns = item.columns.map { "\($0 + 1)" }.joined(separator: ", ")
            let pads = item.padCount == 0 ? "vides" : "\(item.padCount) pad\(item.padCount > 1 ? "s" : "")"
            return "• \(name) : colonne\(item.columns.count > 1 ? "s" : "") \(columns) (\(pads))"
        }
        return "Mis de côté (rien n'est perdu, tout revient si vous désactivez l'option) :\n"
            + lines.joined(separator: "\n") + "\n\nAnnulable avec ⌘Z. Aucun son n'est arrêté."
    }

    private func toggle(_ enabled: Bool) {
        if enabled {
            confirmsActivation = true
        } else {
            controller.setSharedLight(false)
        }
    }
}

extension FocusedValues {
    /// Ouvre les réglages du spectacle de la fenêtre active (menu Spectacle).
    @Entry var showSettingsPresented: Binding<Bool>?
}
