import LalabobDMX
import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Réglages du spectacle (menu Spectacle › Réglages du spectacle…, déverrouillé) : qui pilote la lumière (LightKey ou les
/// projecteurs, J14), l'appareil DMX, et l'option « Mêmes lumières sur toutes les grilles » (fiche 01b) avec son canal.
struct ShowSettingsView: View {
    @Environment(ShowController.self) private var controller
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(DMXSession.self) private var dmx
    /// Activation en attente de confirmation (elle met des colonnes de côté dans les autres grilles).
    @State private var confirmsActivation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Réglages du spectacle")
                .font(.title3.weight(.semibold))

            lightingModeSection
            if controller.isDMXLighting { projectorsSection }

            Divider()

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

    // MARK: - Qui pilote la lumière

    private var lightingModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lumière").font(.body.weight(.medium))
            HStack(spacing: 10) {
                modeChoice(
                    .lightKey, title: "Logiciel lumière",
                    detail: "Lalabob envoie les appuis à LightKey, qui allume les projecteurs et renvoie leur état.")
                modeChoice(
                    .dmx, title: "Projecteurs pilotés par Lalabob",
                    detail: "Lalabob allume la barre lui-même par un boîtier USB-DMX. Pas besoin de logiciel lumière.")
            }
            .disabled(controller.isLocked)
        }
    }

    private func modeChoice(_ mode: LightingMode, title: String, detail: String) -> some View {
        let selected = controller.show.lighting.mode == mode
        return Button {
            controller.setLightingMode(mode)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Surface.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(selected ? Surface.lightAccent.opacity(0.14) : Surface.panel, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Surface.lightAccent : Color.white.opacity(0.08), lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .interactiveCursor(.link, enabled: !controller.isLocked)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Projecteurs

    private var rig: DMXRig { controller.show.lighting.rig }

    private func edit(_ change: (inout DMXRig) -> Void) {
        var updated = rig
        change(&updated)
        controller.setDMXRig(updated)
    }

    private var projectorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Appareil")
                    Text(rig.profile.name).foregroundStyle(Surface.textSecondary)
                }
                GridRow {
                    Text("Adresse")
                    HStack {
                        Stepper(
                            value: Binding(get: { rig.address }, set: { value in edit { $0.address = value } }),
                            in: DMXRig.addressRange(for: rig.profile)
                        ) {
                            Text("\(rig.address)").monospacedDigit()
                        }
                        .fixedSize()
                        Text("celle affichée par la barre : MENU → 15Ch → d \(String(format: "%03d", rig.address))")
                            .font(.caption)
                            .foregroundStyle(Surface.textTertiary)
                    }
                }
                GridRow {
                    Text("Boîtier de ce Mac")
                    HStack(spacing: 8) {
                        Picker("Boîtier", selection: Binding(get: { dmx.selectedPortSerial }, set: { dmx.selectPort(serialNumber: $0) })) {
                            Text("Le premier branché").tag(String?.none)
                            ForEach(dmx.ports) { port in Text(port.name).tag(String?.some(port.serialNumber)) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 240)
                        Circle().fill(dmx.status.isConnected ? Color.green : Surface.textTertiary).frame(width: 8, height: 8)
                        Text(dmx.status.headline).font(.caption).foregroundStyle(Surface.textSecondary)
                    }
                }
                GridRow {
                    Text("Fondu du noir")
                    HStack {
                        Stepper(
                            value: Binding(get: { rig.blackoutFade }, set: { value in edit { $0.blackoutFade = value } }),
                            in: DMXRig.blackoutFadeRange, step: 0.5
                        ) {
                            Text(String(format: "%.1f s", rig.blackoutFade)).monospacedDigit()
                        }
                        .fixedSize()
                    }
                }
                GridRow {
                    Text("Avance de la lumière")
                    HStack {
                        Stepper(
                            value: Binding(get: { rig.lightLead }, set: { value in edit { $0.lightLead = value } }),
                            in: DMXRig.lightLeadRange, step: 0.01
                        ) {
                            Text("\(Int((rig.lightLead * 1000).rounded())) ms").monospacedDigit()
                        }
                        .fixedSize()
                        Text("les alternances basculent un peu avant le temps du son")
                            .font(.caption)
                            .foregroundStyle(Surface.textTertiary)
                    }
                }
                GridRow {
                    Text("En quittant Lalabob")
                    Picker("En quittant Lalabob", selection: Binding(get: { rig.onQuit }, set: { value in edit { $0.onQuit = value } })) {
                        Text("Fondu au noir").tag(DMXRig.QuitBehavior.fadeToBlack)
                        Text("Laisser la lumière").tag(DMXRig.QuitBehavior.leaveLight)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }
            }
            .disabled(controller.isLocked)

            if let detail = dmx.status.detail {
                Text(detail).font(.callout).foregroundStyle(Surface.lightAccent)
            }
            Text(
                "La barre doit être en mode 15 canaux. Si LightKey est ouvert, il ne doit pas piloter ce boîtier en même temps : "
                    + "les deux enverraient à la barre."
            )
            .font(.caption)
            .foregroundStyle(Surface.textTertiary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Essayer : 4 projecteurs en blanc") { dmx.testWhite() }
                Button("Noir") { controller.blackout() }
                Button("Banc d'essai DMX…") { openWindow(id: LalabobCommands.dmxBenchWindowID) }
            }
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
