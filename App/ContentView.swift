import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Jalon 1 : la grille se joue à la souris (mode Live), avec sortie audio et « Tout arrêter ».
/// Le contrôleur arrive au jalon 2.
struct ContentView: View {
    @Environment(ShowController.self) private var controller

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.06))
            GridView()
                .padding(20)
            Spacer(minLength: 0)
        }
        .background(Surface.window)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Lalabob")
                .font(Typography.logo)
                .foregroundStyle(Surface.textPrimary)
            Text(controller.show.name)
                .font(.system(size: 12))
                .foregroundStyle(Surface.textTertiary)
            Spacer()
            controllerStatus
            outputPicker
            modePicker
            Button("Sons d'essai", systemImage: "folder") { controller.loadTrialSounds() }
                .help("Charge les sons du dossier Application Support/Lalabob/Audio de l'app")
            Button("Tout arrêter", systemImage: "stop.fill") { controller.stopAll() }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(.leading, 80)  // laisse la place aux boutons de fenêtre
        .padding(.trailing, 20)
        .frame(height: 52)
        .background(Surface.chrome)
    }

    private var controllerStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(controller.connectedControllerName == nil ? Surface.textTertiary : Color.green)
                .frame(width: 8, height: 8)
            Text(controller.connectedControllerName ?? "Aucun contrôleur")
                .font(.system(size: 12))
                .foregroundStyle(Surface.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(controller.connectedControllerName.map { "\($0), connecté" } ?? "Aucun contrôleur connecté")
    }

    private var outputPicker: some View {
        @Bindable var controller = controller
        return Picker("Sortie audio", selection: Binding(get: { controller.selectedOutputUID }, set: { controller.selectOutput(uid: $0) })) {
            Text("Sortie par défaut").tag(String?.none)
            ForEach(controller.outputDevices) { device in
                Text(device.name).tag(String?.some(device.uid))
            }
        }
        .labelsHidden()
        .frame(width: 200)
        .help("Sortie audio")
    }

    private var modePicker: some View {
        Picker("Mode", selection: Bindable(controller).mode) {
            Text("Édition").tag(InteractionMode.edit)
            Text("Live").tag(InteractionMode.live)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 150)
    }
}

struct GridView: View {
    @Environment(ShowController.self) private var controller

    var body: some View {
        let grid = controller.currentGrid
        HStack(alignment: .top, spacing: 16) {
            HStack(spacing: Metrics.columnSpacing) {
                ForEach(indices(of: .audio, in: grid), id: \.self) { index in
                    ColumnView(index: index)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: Metrics.columnSpacing) {
                ForEach(indices(of: .light, in: grid), id: \.self) { index in
                    ColumnView(index: index)
                }
            }
            .padding(8)
            .background(Surface.lightZone, in: .rect(cornerRadius: Metrics.panelCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.panelCornerRadius)
                    .stroke(Surface.lightAccent.opacity(0.12))
            )
            .frame(width: 280)
        }
    }

    private func indices(of kind: ColumnKind, in grid: PadGrid) -> [Int] {
        grid.columns.indices.filter { grid.columns[$0].kind == kind }
    }
}

struct ColumnView: View {
    @Environment(ShowController.self) private var controller
    let index: Int

    var body: some View {
        let column = controller.currentGrid.columns[index]
        VStack(spacing: Metrics.padSpacing) {
            HStack(spacing: 8) {
                Image(systemName: column.kind == .audio ? "music.note" : "lightbulb.max.fill")
                    .foregroundStyle(column.kind == .audio ? Surface.textSecondary : Surface.lightAccent)
                Text(column.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Surface.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 30)

            ForEach(0..<PadGrid.size, id: \.self) { row in
                PadView(position: GridPosition(column: index, row: row), kind: column.kind)
            }

            if column.kind == .audio {
                // Fader provisoire (horizontal) ; le fader vertical de la maquette arrive au jalon 5.
                Slider(value: Binding(get: { column.level }, set: { controller.setColumnLevel(index, level: $0) }), in: 0...1)
                    .controlSize(.small)
                    .accessibilityLabel("Volume de \(column.name)")
            }
        }
        .frame(minWidth: 110, maxWidth: .infinity)
    }
}

struct PadView: View {
    @Environment(ShowController.self) private var controller
    let position: GridPosition
    let kind: ColumnKind

    var body: some View {
        let pad = controller.pad(at: position)
        let event = pad.flatMap { controller.playback[$0.id] }
        let isSelected = controller.selection == position

        Button {
            controller.press(at: position)
        } label: {
            Group {
                if let pad {
                    filled(pad, event: event)
                } else {
                    empty
                }
            }
            .frame(height: Metrics.padHeight)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Metrics.padCornerRadius).stroke(.white, lineWidth: 2)
                }
            }
            .contentShape(.rect(cornerRadius: Metrics.padCornerRadius))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if pad != nil, kind == .audio {
                Button("Pause / Reprendre") { controller.togglePause(at: position) }
                Button("Arrêter") { controller.stop(at: position) }
            }
        }
        .accessibilityLabel(pad.map { "\($0.title), \($0.subtitle)" } ?? "Case vide")
    }

    private func filled(_ pad: Pad, event: PlaybackEvent?) -> some View {
        let vivid = pad.tint.vividColor
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(pad.title).font(Typography.padTitle).lineLimit(1)
                Spacer(minLength: 0)
                if case .paused = event?.state { Image(systemName: "pause.fill").font(.system(size: 10)) }
                if case .playing = event?.state { Image(systemName: "waveform").font(.system(size: 10)) }
            }
            Text(pad.subtitle).font(Typography.padSubtitle).opacity(0.88).lineLimit(1)
        }
        .foregroundStyle(pad.tint.labelColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .background(pad.tint.surfaceColor, in: .rect(cornerRadius: Metrics.padCornerRadius))
        .overlay(alignment: .bottom) { progressBar(event, color: vivid) }
        .overlay {
            if let event {
                RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                    .stroke(vivid.opacity(event.state.isPaused ? 0.45 : 1), lineWidth: 2)
            }
        }
        .shadow(color: event.map { $0.state.isPaused ? .clear : vivid.opacity(0.45) } ?? .clear, radius: 8)
    }

    /// Barre de progression de 3 px ; figée et estompée en pause. Une boucle revient au début.
    @ViewBuilder
    private func progressBar(_ event: PlaybackEvent?, color: Color) -> some View {
        if let event, event.duration > 0 {
            TimelineView(.animation(paused: event.state.isPaused)) { _ in
                GeometryReader { geometry in
                    let elapsed = event.state.elapsed(now: ProcessInfo.processInfo.systemUptime)
                    let fraction = min(max(elapsed.truncatingRemainder(dividingBy: event.duration) / event.duration, 0), 1)
                    Capsule()
                        .fill(color.opacity(event.state.isPaused ? 0.4 : 1))
                        .frame(width: geometry.size.width * fraction, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }

    private var empty: some View {
        Label(kind == .audio ? "Déposer un son" : "Nouvelle cue", systemImage: "plus")
            .font(.system(size: 11.5))
            .foregroundStyle(Surface.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.padCornerRadius)
                    .strokeBorder(Surface.emptyPadStroke, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
    }
}

private extension PlaybackState {
    var isPaused: Bool {
        if case .paused = self { true } else { false }
    }

    /// Temps écoulé en secondes.
    func elapsed(now: TimeInterval) -> TimeInterval {
        switch self {
        case .idle: 0
        case .playing(let startedAt): now - startedAt
        case .paused(let elapsed): elapsed
        }
    }
}

#Preview {
    ContentView()
        .environment(ShowController())
        .frame(width: 1400, height: 760)
        .preferredColorScheme(.dark)
}
