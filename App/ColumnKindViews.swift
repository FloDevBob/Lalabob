import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Pastille de type de l'en-tête d'une colonne : note (son), projecteur (lumière), les deux (son et lumière).
/// Déverrouillé, c'est un bouton qui ouvre le choix du type (popover) ; verrouillé, une simple image.
struct ColumnKindPill: View {
    @Environment(ShowController.self) private var controller
    @Environment(ConversionPrompter.self) private var prompter
    let index: Int
    let kind: ColumnKind
    let name: String

    @State private var shown = false

    private var tint: Color { kind == .audio ? Surface.textSecondary : Surface.lightAccent }

    var body: some View {
        if controller.isLocked {
            pill(showsChevron: false)
                .accessibilityLabel("Type de la colonne : \(kind.title)")
        } else {
            Button { shown.toggle() } label: { pill(showsChevron: true) }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 8)
                .interactiveCursor(.link)
                .help("Type de la colonne : \(kind.title) — cliquer pour le changer")
                .accessibilityLabel("Type de la colonne : \(kind.title)")
                .accessibilityHint("Ouvre le choix du type de la colonne")
                .popover(isPresented: $shown, arrowEdge: .bottom) { popover }
        }
    }

    private func pill(showsChevron: Bool) -> some View {
        HStack(spacing: 3) {
            if kind.hasAudio { Icon.music.view(size: 14).foregroundStyle(Surface.textSecondary) }
            if kind != .audio { Icon.spotlight.view(size: 14).foregroundStyle(Surface.lightAccent) }
            if showsChevron {
                ColumnChevron()
                    .stroke(Surface.textTertiary, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 7, height: 4)
                    .padding(.leading, 1)
            }
        }
        .padding(.horizontal, 6)
        .frame(minWidth: 26, minHeight: 26)
        .background(tint.opacity(kind == .audio ? 0.12 : 0.14), in: .rect(cornerRadius: 8))
        .overlay {
            if kind == .mixed { RoundedRectangle(cornerRadius: 8).strokeBorder(Surface.lightAccent.opacity(0.35)) }
        }
        .contentShape(.rect(cornerRadius: 8))
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TYPE DE LA COLONNE « \(name.uppercased()) »")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Surface.textTertiary)
                .lineLimit(1)
            ForEach([ColumnKind.audio, .mixed, .light], id: \.self) { option in
                row(option)
            }
            Text("Élargir ne retire rien. Restreindre demande confirmation et s'annule avec ⌘Z.")
                .font(.system(size: 11.5))
                .foregroundStyle(Surface.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 340)
    }

    private func row(_ option: ColumnKind) -> some View {
        let isCurrent = option == kind
        let problem = isCurrent ? nil : controller.columnKindProblem(index, to: option)
        return Button {
            shown = false
            prompter.requestColumnKind(index, to: option, controller: controller)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .strokeBorder(isCurrent ? Surface.lightAccent : Surface.textTertiary, lineWidth: 1.5)
                    .background { if isCurrent { Circle().fill(Surface.lightAccent).padding(3.5) } }
                    .frame(width: 14, height: 14)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title).font(.system(size: 13, weight: .semibold))
                    Text(problem ?? option.explanation)
                        .font(.system(size: 11.5))
                        .foregroundStyle(problem == nil ? Surface.textSecondary : Surface.lightAccent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? Color.white.opacity(0.08) : Color.clear, in: .rect(cornerRadius: 10))
            .overlay {
                if isCurrent { RoundedRectangle(cornerRadius: 10).strokeBorder(Surface.lightAccent.opacity(0.4)) }
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(problem != nil)
        .hoverHighlight(cornerRadius: 10, enabled: !isCurrent && problem == nil)
        .interactiveCursor(.link, enabled: problem == nil)
        .accessibilityLabel(option.title)
        .accessibilityValue(option.explanation)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Menu du clic droit sur l'en-tête d'une colonne : renommer, type, arrêter les sons, vider. Verrouillé : seulement arrêter.
struct ColumnContextMenu: View {
    @Environment(ShowController.self) private var controller
    @Environment(ConversionPrompter.self) private var prompter
    let index: Int
    let rename: () -> Void

    var body: some View {
        let column = controller.currentGrid.columns[index]
        if !controller.isLocked {
            Button("Renommer…", action: rename)
            Menu("Type de colonne") {
                ForEach([ColumnKind.audio, .mixed, .light], id: \.self) { option in
                    let isCurrent = option == column.kind
                    let lossy = !isCurrent && !controller.conversionPlan(column: index, to: option).isLossless
                    Button {
                        prompter.requestColumnKind(index, to: option, controller: controller)
                    } label: {
                        Text((isCurrent ? "✓ " : "") + option.title + (lossy ? "…" : ""))
                    }
                    .disabled(isCurrent || controller.columnKindProblem(index, to: option) != nil)
                }
            }
            Divider()
        }
        if column.kind.hasAudio {
            Button("Arrêter les sons de la colonne", icon: .stop) { controller.stopColumn(index) }
        }
        if !controller.isLocked {
            Button("Vider la colonne…", icon: .trash) { prompter.requestClearColumn(index, controller: controller) }
                .disabled(column.slots.allSatisfy { $0 == nil })
        }
    }
}

/// Liseré de type sous l'en-tête d'une colonne : discret pour un son, ambre plein pour la lumière, ambre pointillé pour son et lumière.
struct ColumnKindRule: View {
    let kind: ColumnKind

    var body: some View {
        Group {
            switch kind {
            case .audio:
                Capsule().fill(Color.white.opacity(0.06)).frame(height: 2)
            case .light:
                Capsule().fill(Surface.lightAccent.opacity(0.85)).frame(height: 2)
            case .mixed:
                HorizontalLine()
                    .stroke(Surface.lightAccent.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
                    .frame(height: 2)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }
}

private nonisolated struct HorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private nonisolated struct ColumnChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
