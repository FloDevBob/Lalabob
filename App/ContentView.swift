import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Jalon 0 : la fenêtre affiche la grille vide aux couleurs de la maquette.
/// La lecture audio arrive au jalon 1, le contrôleur au jalon 2.
struct ContentView: View {
    @Environment(ShowController.self) private var controller

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.06))
            GridView(grid: controller.currentGrid)
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
        }
        .padding(.horizontal, 80)  // laisse la place aux boutons de fenêtre
        .frame(height: 52)
        .background(Surface.chrome)
    }
}

struct GridView: View {
    let grid: Grid

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            HStack(spacing: Metrics.columnSpacing) {
                ForEach(indices(of: .audio), id: \.self) { index in
                    ColumnView(column: grid.columns[index])
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: Metrics.columnSpacing) {
                ForEach(indices(of: .light), id: \.self) { index in
                    ColumnView(column: grid.columns[index])
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

    private func indices(of kind: ColumnKind) -> [Int] {
        grid.columns.indices.filter { grid.columns[$0].kind == kind }
    }
}

struct ColumnView: View {
    let column: Column

    var body: some View {
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

            ForEach(0..<Grid.size, id: \.self) { row in
                PadView(pad: column.slots[row], kind: column.kind)
            }
        }
        .frame(minWidth: 110, maxWidth: .infinity)
    }
}

struct PadView: View {
    let pad: Pad?
    let kind: ColumnKind

    var body: some View {
        Group {
            if let pad {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pad.title).font(Typography.padTitle).lineLimit(1)
                    Text(pad.subtitle).font(Typography.padSubtitle).opacity(0.88).lineLimit(1)
                }
                .foregroundStyle(pad.tint.labelColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .background(pad.tint.surfaceColor, in: .rect(cornerRadius: Metrics.padCornerRadius))
            } else {
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
        .frame(height: Metrics.padHeight)
    }
}

#Preview {
    ContentView()
        .environment(ShowController())
        .frame(width: 1400, height: 760)
        .preferredColorScheme(.dark)
}
