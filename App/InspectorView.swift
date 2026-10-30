import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Inspecteur minimal (J4) : titre, sous-titre, couleur, intensité LED, et actions du presse-papiers.
/// Forme d'onde, élagage et fondus arrivent au J5.
struct InspectorView: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition

    @State private var title = ""
    @State private var subtitle = ""
    @FocusState private var focusedField: Field?

    private enum Field { case title, subtitle }

    var body: some View {
        let pad = controller.pad(at: position)
        VStack(alignment: .leading, spacing: 14) {
            header(pad)
            if let pad {
                HStack(alignment: .top, spacing: 28) {
                    texts
                        .frame(width: 300)
                    colors(selected: pad.tint)
                    intensity(selected: pad.ledIntensity)
                    Spacer(minLength: 0)
                }
            } else {
                emptyCell
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(Surface.panel)
        .onAppear { load(pad) }
        .onChange(of: position) { load(controller.pad(at: position)) }
        .onChange(of: pad) { if focusedField == nil { load(pad) } }
        .onChange(of: focusedField) { old, _ in
            if old == .title { commitTitle() }
            if old == .subtitle { commitSubtitle() }
        }
    }

    // MARK: - Parties

    private func header(_ pad: Pad?) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(pad?.tint.vividColor ?? Surface.textTertiary)
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(pad?.title ?? "Case vide")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Surface.textPrimary)
                Text(controller.positionLabel(for: position))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Surface.textTertiary)
            }
            Spacer()
            Group {
                Button("Couper", icon: .cut) { controller.cutSelection() }
                    .disabled(pad == nil)
                Button("Copier", icon: .copy) { controller.copySelection() }
                    .disabled(pad == nil)
                Button("Coller", icon: .paste) { controller.pasteAtSelection() }
                    .disabled(!controller.canPaste)
                Button("Dupliquer", icon: .duplicate) { controller.duplicateSelection() }
                    .disabled(pad == nil)
                Button("Vider", icon: .trash) { controller.clearSelection() }
                    .disabled(pad == nil)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Titre").font(.system(size: 11)).foregroundStyle(Surface.textTertiary)
            TextField("Titre", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .title)
                .onSubmit(commitTitle)
            Text("Sous-titre").font(.system(size: 11)).foregroundStyle(Surface.textTertiary)
            TextField("Sous-titre", text: $subtitle)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .subtitle)
                .onSubmit(commitSubtitle)
        }
    }

    private func colors(selected: Tint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couleur du pad").font(.system(size: 11)).foregroundStyle(Surface.textTertiary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8), spacing: 6) {
                ForEach(Tint.allCases, id: \.self) { tint in
                    Button {
                        controller.updatePad(at: position, tint: tint)
                    } label: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tint.surfaceColor)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().fill(tint.vividColor).frame(width: 10, height: 10))
                            .overlay {
                                if tint == selected {
                                    RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(tint.displayName)
                    .accessibilityLabel(tint.displayName)
                    .accessibilityAddTraits(tint == selected ? .isSelected : [])
                }
            }
        }
    }

    private func intensity(selected: LEDIntensity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Intensité LED").font(.system(size: 11)).foregroundStyle(Surface.textTertiary)
            Picker(
                "Intensité LED",
                selection: Binding(get: { selected }, set: { controller.updatePad(at: position, ledIntensity: $0) })
            ) {
                ForEach(LEDIntensity.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
        }
    }

    @ViewBuilder
    private var emptyCell: some View {
        if controller.currentGrid.columns[position.column].kind == .light {
            Button("Nouvelle cue", icon: .plus) { controller.newLightCue(at: position) }
            Text("LightKey reçoit la note de cette case : réglez son mapping MIDI sur le contrôleur.")
                .font(.system(size: 11.5))
                .foregroundStyle(Surface.textTertiary)
        } else {
            Text("Glissez un son de la bibliothèque ou du Finder sur cette case.")
                .font(.system(size: 12))
                .foregroundStyle(Surface.textTertiary)
        }
    }

    // MARK: - Texte

    private func load(_ pad: Pad?) {
        title = pad?.title ?? ""
        subtitle = pad?.subtitle ?? ""
    }

    private func commitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            load(controller.pad(at: position))  // un titre vide n'est pas accepté
            return
        }
        controller.updatePad(at: position, title: trimmed)
    }

    private func commitSubtitle() {
        controller.updatePad(at: position, subtitle: subtitle.trimmingCharacters(in: .whitespaces))
    }
}
