import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

// Panneau du bas d'un pad lumière en mode Projecteurs (J14, étape 4c) : la bande du haut (Essayer, titre, fondu d'entrée,
// nouvel appui, couleur du pad) et la bande du bas (type de l'état, puis ses réglages). Maquette : planches « Inspecteur »,
// « InspEnsemble », « InspAlternance », « InspProgramme », « InspSon » (plan J14).

extension Color {
    /// La couleur de la roue telle qu'on la voit à l'écran (pleine intensité).
    init(light: LightColor) {
        let rgb = light.rgb
        self.init(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}

// MARK: - Bande du haut

struct DMXLightHeader: View {
    @Environment(ShowController.self) private var controller
    @Environment(DMXSession.self) private var dmx
    let position: GridPosition
    let pad: Pad

    var body: some View {
        HStack(spacing: 12) {
            TitleFields(position: position, pad: pad)
            Spacer(minLength: 8)
            Button("Essayer", icon: .spotlight, size: 12) { controller.testCue(at: position) }
                .buttonStyle(.borderedProminent)
                .tint(Surface.lightAccent)
                .foregroundStyle(Surface.window)
                .controlSize(.small)
                .help("Joue cet état sur les projecteurs, comme un appui sur le pad")
            HeaderDivider()
            previewToggle
            fadeStepper
            retriggerMenu
            HeaderDivider()
            ColorPopoverButton(position: position, pad: pad)
            PadActionsMenu(position: position, hasPad: true)
        }
        .padding(.horizontal, 14)
    }

    /// « Aperçu sur la barre » : chaque réglage se voit tout de suite sur les projecteurs (jamais verrouillé).
    private var previewToggle: some View {
        @Bindable var dmx = dmx
        return HStack(spacing: 5) {
            Text("Aperçu").font(.system(size: 10)).foregroundStyle(Surface.textTertiary)
            Toggle("Aperçu sur la barre", isOn: $dmx.isLivePreviewEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .help("Aperçu sur la barre : chaque réglage s'applique tout de suite aux projecteurs, sans fondu. En quittant le pad, la barre revient à la lumière d'avant.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Aperçu sur la barre")
    }

    private var fadeIn: Double { controller.effectiveLook(at: position)?.fadeIn ?? LightLook.defaultFadeIn }

    private var fadeStepper: some View {
        HStack(spacing: 4) {
            Text("Fondu").font(.system(size: 10)).foregroundStyle(Surface.textTertiary)
            stepButton("−", delta: -0.5, help: "Fondu plus court")
            Text(String(format: "%.1f s", fadeIn))
                .font(Typography.mono)
                .frame(minWidth: 40)
                .foregroundStyle(Surface.textSecondary)
            stepButton("+", delta: 0.5, help: "Fondu plus long")
        }
        .disabled(controller.isLocked)
        .help("Durée du fondu depuis la lumière en cours quand ce pad est joué")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fondu d'entrée")
    }

    private func stepButton(_ title: String, delta: Double, help: String) -> some View {
        Button(title) {
            guard var look = controller.effectiveLook(at: position) else { return }
            let range = LightLook.fadeInRange
            look.fadeIn = min(max((fadeIn + delta).rounded(toPlaces: 1), range.lowerBound), range.upperBound)
            controller.setLook(at: position, to: look)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(help)
    }

    private var retriggerMenu: some View {
        HStack(spacing: 6) {
            Text("Nouvel appui").font(.system(size: 10)).foregroundStyle(Surface.textTertiary).lineLimit(1)
            Picker(
                "Nouvel appui",
                selection: Binding(
                    get: { pad.lightRetrigger }, set: { controller.setLightRetrigger(at: position, to: $0) })
            ) {
                Text("Laisse allumé").tag(LightRetrigger.turnOnOnly)
                Text("Allume ou éteint").tag(LightRetrigger.toggle)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 130)
            .disabled(controller.isLocked)
            .help("Si on rejoue ce pad pendant qu'il éclaire : le laisser allumé, ou l'éteindre en fondu")
        }
        .fixedSize()
    }
}

extension Double {
    fileprivate func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}

// MARK: - Bande du bas

struct DMXLookPanel: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let pad: Pad

    /// État en cours de réglage (pendant un glissé) : il n'entre dans le spectacle — et dans ⌘Z — qu'au relâchement.
    @State private var draft: LightLook?

    private var profile: FixtureProfile { controller.show.lighting.rig.profile }
    private var look: LightLook { draft ?? controller.effectiveLook(at: position) ?? LightLook.uniform(color: .white, intensity: 1, headCount: profile.headCount) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            stylePicker
            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .disabled(controller.isLocked)
        .id(pad.id)
        .onChange(of: pad.id) { draft = nil }
        .onDisappear { controller.endLookPreview() }  // on quitte le pad : la barre revient à la lumière d'avant
    }

    // MARK: Modifications

    /// Modifie l'état : tout de suite dans le spectacle (clic), ou en brouillon tant qu'on glisse (`final: false`).
    private func edit(final: Bool = true, _ change: (inout LightLook) -> Void) {
        var updated = look
        change(&updated)
        if final {
            draft = nil
            controller.setLook(at: position, to: updated)
        } else {
            draft = updated
            controller.previewLook(at: position, updated)  // le glissé se voit tout de suite sur la barre
        }
    }

    private func commitDraft() {
        guard let draft else { return }
        self.draft = nil
        controller.setLook(at: position, to: draft)
    }

    /// Un curseur dont le glissé reste un brouillon, validé au relâchement.
    private func slider(_ value: Double, in range: ClosedRange<Double> = 0...1, label: String, set: @escaping (inout LightLook, Double) -> Void) -> some View {
        Slider(
            value: Binding(get: { value }, set: { new in edit(final: false) { set(&$0, new) } }), in: range,
            onEditingChanged: { editing in if !editing { commitDraft() } }
        )
        .controlSize(.small)
        .accessibilityLabel(label)
    }

    // MARK: Type

    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Type").font(.system(size: 10)).foregroundStyle(Surface.textTertiary)
            ForEach(profile.supportedLookStyles, id: \.self) { style in
                let selected = look.content.style == style
                Button {
                    controller.setLookStyle(at: position, to: style)
                } label: {
                    Text(style.title)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .frame(width: 92, height: 22, alignment: .leading)
                        .padding(.horizontal, 8)
                        .background(selected ? Surface.lightAccent.opacity(0.2) : Color.white.opacity(0.05), in: .rect(cornerRadius: 7))
                        .foregroundStyle(selected ? Surface.lightAccent : Surface.textSecondary)
                }
                .buttonStyle(.plain)
                .interactiveCursor(.link)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    // MARK: Contenu selon le type

    @ViewBuilder
    private var content: some View {
        switch look.content {
        case .colors(let colors): colorsEditor(colors)
        case .alternate(let alternate): alternateEditor(alternate)
        case .fixtureProgram(let number, let speed): programEditor(number: number, speed: speed)
        case .soundActive(let sensitivity): soundEditor(sensitivity)
        }
    }

    private func updateColors(final: Bool = true, _ change: @escaping (inout ColorsLook) -> Void) {
        edit(final: final) { look in
            guard case .colors(var colors) = look.content else { return }
            change(&colors)
            look.content = .colors(colors)
        }
    }

    // Couleurs : Chacun / Ensemble, puis des cartes de projecteurs, puis le strobo.
    private func colorsEditor(_ colors: ColorsLook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(
                "Réglage",
                selection: Binding(
                    get: { colors.linked },
                    set: { linked in
                        // Vers « Ensemble » : les quatre prennent la couleur du premier projecteur allumé.
                        let source = colors.heads.firstIndex { $0.isOn } ?? 0
                        updateColors { $0 = $0.settingLinked(linked, source: source) }
                    })
            ) {
                Text("Chacun").tag(false)
                Text("Ensemble").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 180)
            .help("Chacun : une couleur par projecteur. Ensemble : la même couleur et la même intensité pour tous.")

            HStack(alignment: .top, spacing: 10) {
                if colors.linked {
                    linkedCard(colors)
                } else {
                    ForEach(colors.heads.indices, id: \.self) { index in headCard(index, colors.heads[index]) }
                }
                strobeCard(colors)
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Surface.textTertiary)
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 10))
    }

    private func headCard(_ index: Int, _ head: HeadLook) -> some View {
        card("Projecteur \(index + 1)") {
            HStack(spacing: 6) {
                Toggle("Allumé", isOn: Binding(get: { head.isOn }, set: { on in updateColors { $0.heads[index].isOn = on } }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help("Allumer ou éteindre le projecteur \(index + 1) dans cet état")
                ColorSwatchButton(color: head.color, label: "Couleur du projecteur \(index + 1)") { color, final in
                    updateColors(final: final) { $0.heads[index].color = color }
                }
            }
            slider(head.intensity, label: "Intensité du projecteur \(index + 1)") { look, value in
                guard case .colors(var colors) = look.content else { return }
                colors.heads[index].intensity = value
                look.content = .colors(colors)
            }
            .opacity(head.isOn ? 1 : 0.4)
        }
    }

    private func linkedCard(_ colors: ColorsLook) -> some View {
        let first = colors.heads.first ?? HeadLook(isOn: true, color: .white, intensity: 1)
        return card("Les \(colors.heads.count) projecteurs ensemble") {
            HStack(spacing: 8) {
                ColorSwatchButton(color: first.color, label: "Couleur des projecteurs") { color, final in
                    updateColors(final: final) { colors in colors.heads.indices.forEach { colors.heads[$0].color = color } }
                }
                ForEach(colors.heads.indices, id: \.self) { index in
                    let on = colors.heads[index].isOn
                    Button("\(index + 1)") { updateColors { $0.heads[index].isOn.toggle() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(width: 22, height: 22)
                        .background(on ? Surface.lightAccent : Color.white.opacity(0.08), in: .circle)
                        .foregroundStyle(on ? Surface.window : Surface.textSecondary)
                        .interactiveCursor(.link)
                        .help("Projecteur \(index + 1) : \(on ? "allumé" : "éteint")")
                        .accessibilityLabel("Projecteur \(index + 1)")
                        .accessibilityValue(on ? "allumé" : "éteint")
                }
            }
            slider(first.intensity, label: "Intensité") { look, value in
                guard case .colors(var colors) = look.content else { return }
                colors.heads.indices.forEach { colors.heads[$0].intensity = value }
                look.content = .colors(colors)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func strobeCard(_ colors: ColorsLook) -> some View {
        card("Strobo") {
            Toggle(
                "Strobo",
                isOn: Binding(get: { colors.strobe != nil }, set: { on in updateColors { $0.strobe = on ? 0.3 : nil } })
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help("Faire clignoter la barre (arrêté par défaut, jamais déclenché par erreur)")
            if let strobe = colors.strobe {
                slider(strobe, label: "Vitesse du strobo") { look, value in
                    guard case .colors(var colors) = look.content else { return }
                    colors.strobe = max(value, 0.01)
                    look.content = .colors(colors)
                }
            } else {
                Text("Arrêté").font(.system(size: 11)).foregroundStyle(Surface.textTertiary)
            }
        }
        .frame(width: 120)
    }

    // Alternance : deux couleurs en damier.
    private func updateAlternate(final: Bool = true, _ change: @escaping (inout AlternateLook) -> Void) {
        edit(final: final) { look in
            guard case .alternate(var alternate) = look.content else { return }
            change(&alternate)
            look.content = .alternate(alternate)
        }
    }

    private func alternateEditor(_ alternate: AlternateLook) -> some View {
        HStack(alignment: .top, spacing: 10) {
            card("Couleur A · projecteurs 1 et 3") {
                ColorSwatchButton(color: alternate.a, label: "Couleur A") { color, final in
                    updateAlternate(final: final) { $0.a = color }
                }
            }
            card("Couleur B · projecteurs 2 et 4") {
                ColorSwatchButton(color: alternate.b, label: "Couleur B") { color, final in
                    updateAlternate(final: final) { $0.b = color }
                }
            }
            card("Bascule") {
                Picker(
                    "Bascule",
                    selection: Binding(get: { alternate.every }, set: { value in updateAlternate { $0.every = value } })
                ) {
                    Text("1 temps").tag(AlternateLook.Interval.beat)
                    Text("2 temps").tag(AlternateLook.Interval.twoBeats)
                    Text("1 mesure").tag(AlternateLook.Interval.bar)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                HStack(spacing: 6) {
                    Text("Fondu").font(.system(size: 10)).foregroundStyle(Surface.textTertiary)
                    slider(alternate.switchFade, in: 0...0.5, label: "Fondu à la bascule") { look, value in
                        guard case .alternate(var alternate) = look.content else { return }
                        alternate.switchFade = value
                        look.content = .alternate(alternate)
                    }
                    Text(alternate.switchFade == 0 ? "net" : String(format: "%.2f s", alternate.switchFade))
                        .font(Typography.mono)
                        .foregroundStyle(Surface.textSecondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .frame(minWidth: 220)
            card("Tempo de repli") {
                Stepper(
                    value: Binding(
                        get: { alternate.fallbackBPM }, set: { value in updateAlternate { $0.fallbackBPM = value } }),
                    in: 40...240, step: 1
                ) {
                    Text("\(Int(alternate.fallbackBPM.rounded())) BPM").font(Typography.mono)
                }
                .controlSize(.small)
                Text("Sans son rythmé en cours").font(.system(size: 10)).foregroundStyle(Surface.textTertiary)
            }
            .frame(width: 140)
        }
    }

    // Programme de la barre.
    private func programEditor(number: Int, speed: Double) -> some View {
        let count = profile.programs?.count ?? 0
        return HStack(alignment: .top, spacing: 10) {
            card("Programme de la barre") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 6), spacing: 4) {
                    ForEach(1...max(count, 1), id: \.self) { index in
                        let selected = index == number
                        Button("\(index)") {
                            edit { $0.content = .fixtureProgram(number: index, speed: speed) }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .frame(width: 30, height: 24)
                        .background(selected ? Surface.lightAccent : Color.white.opacity(0.08), in: .rect(cornerRadius: 6))
                        .foregroundStyle(selected ? Surface.window : Surface.textSecondary)
                        .interactiveCursor(.link)
                        .accessibilityLabel("Programme \(index)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .frame(width: 240)
            card("Vitesse") {
                slider(speed, label: "Vitesse du programme") { look, value in look.content = .fixtureProgram(number: number, speed: value) }
                Text("\(Int((speed * 100).rounded())) %").font(Typography.mono).foregroundStyle(Surface.textSecondary)
            }
            .frame(width: 200)
        }
    }

    // Sur le son : le micro de la barre.
    private func soundEditor(_ sensitivity: Double) -> some View {
        HStack(alignment: .top, spacing: 10) {
            card("Sensibilité du micro") {
                slider(sensitivity, label: "Sensibilité au son") { look, value in look.content = .soundActive(sensitivity: value) }
                Text("\(Int((sensitivity * 100).rounded())) %").font(Typography.mono).foregroundStyle(Surface.textSecondary)
            }
            .frame(width: 220)
            Text(
                "La barre écoute son propre micro et choisit ses couleurs. Il entend toute la salle : voix, rires, applaudissements — "
                    + "pas seulement les sons de Lalabob."
            )
            .font(.system(size: 11.5))
            .foregroundStyle(Surface.lightAccent)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 320, alignment: .leading)
        }
    }
}

// MARK: - Pastille de couleur et roue

/// Une pastille de la couleur d'un projecteur ; un clic ouvre la roue des couleurs. `onChange(couleur, final)` : `final` est
/// faux pendant un glissé sur la roue, vrai au relâchement ou pour un choix direct (favori).
struct ColorSwatchButton: View {
    @Environment(ShowController.self) private var controller
    let color: LightColor
    let label: String
    let onChange: (LightColor, Bool) -> Void

    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(light: color))
                .frame(width: 34, height: 22)
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.25), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .interactiveCursor(.link)
        .help("Choisir la couleur")
        .accessibilityLabel(label)
        .popover(isPresented: $shown, arrowEdge: .top) {
            ColorWheelPopover(
                color: color, favorites: controller.show.lighting.rig.favoriteColors, onChange: onChange,
                onToggleFavorite: { controller.toggleFavoriteColor($0) })
        }
    }
}

/// La roue : l'angle est la teinte, la distance au centre la saturation (centre = blanc, bord = intense). Deux curseurs
/// donnent le même réglage au clavier ; en dessous, les couleurs du spectacle.
private struct ColorWheelPopover: View {
    let color: LightColor
    let favorites: [LightColor]
    let onChange: (LightColor, Bool) -> Void
    let onToggleFavorite: (LightColor) -> Void

    @State private var live: LightColor?

    private var current: LightColor { live ?? color }
    private static let diameter: CGFloat = 150

    var body: some View {
        VStack(spacing: 10) {
            wheel
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6).fill(Color(light: current)).frame(width: 34, height: 22)
                VStack(spacing: 2) {
                    labeled("Teinte", value: current.hue, range: 0...359) { LightColor(hue: $0, saturation: current.saturation) }
                    labeled("Pâle → intense", value: current.saturation, range: 0...1) { LightColor(hue: current.hue, saturation: $0) }
                }
            }
            HStack(spacing: 5) {
                ForEach(Array(favorites.enumerated()), id: \.offset) { _, favorite in
                    Button { onChange(favorite, true) } label: {
                        Circle().fill(Color(light: favorite)).frame(width: 18, height: 18)
                            .overlay { Circle().stroke(Color.white.opacity(favorite == current ? 1 : 0.2), lineWidth: 1.5) }
                    }
                    .buttonStyle(.plain)
                    .interactiveCursor(.link)
                    .accessibilityLabel("Couleur du spectacle")
                }
                Button { onToggleFavorite(current) } label: {
                    Text(favorites.contains(current) ? "−" : "+")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.1), in: .circle)
                }
                .buttonStyle(.plain)
                .interactiveCursor(.link)
                .help(favorites.contains(current) ? "Retirer des couleurs du spectacle" : "Garder cette couleur dans le spectacle")
                .accessibilityLabel(favorites.contains(current) ? "Retirer des couleurs du spectacle" : "Garder cette couleur")
                Spacer(minLength: 0)
            }
            .frame(width: Self.diameter + 20)
        }
        .padding(14)
    }

    private func labeled(_ title: String, value: Double, range: ClosedRange<Double>, make: @escaping (Double) -> LightColor) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(Surface.textTertiary).frame(width: 78, alignment: .leading)
            Slider(
                value: Binding(get: { value }, set: { live = make($0); onChange(make($0), false) }), in: range,
                onEditingChanged: { editing in if !editing, let live { onChange(live, true) } }
            )
            .controlSize(.mini)
            .accessibilityLabel(title)
        }
        .frame(width: 150)
    }

    private var wheel: some View {
        let hues = (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) }
        return ZStack {
            Circle().fill(AngularGradient(colors: hues, center: .center, angle: .degrees(-90)))
            Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: Self.diameter / 2))
            // Repère de la couleur en cours.
            let radius = Self.diameter / 2 * current.saturation
            let angle = (current.hue - 90) * .pi / 180
            Circle()
                .stroke(.white, lineWidth: 2)
                .background(Circle().fill(Color(light: current)))
                .frame(width: 16, height: 16)
                .shadow(radius: 2)
                .offset(x: radius * cos(angle), y: radius * sin(angle))
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let new = Self.color(at: drag.location, diameter: Self.diameter)
                    live = new
                    onChange(new, false)
                }
                .onEnded { drag in
                    let new = Self.color(at: drag.location, diameter: Self.diameter)
                    live = nil
                    onChange(new, true)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Roue des couleurs")
        .accessibilityHint("Utilisez les curseurs Teinte et Pâle à intense")
    }

    /// Teinte et saturation d'un point de la roue (0 en haut, dans le sens des aiguilles d'une montre).
    static func color(at point: CGPoint, diameter: CGFloat) -> LightColor {
        let radius = diameter / 2
        let dx = point.x - radius, dy = point.y - radius
        var degrees = atan2(dy, dx) * 180 / .pi + 90
        if degrees < 0 { degrees += 360 }
        return LightColor(hue: degrees, saturation: min(hypot(dx, dy) / radius, 1))
    }
}
