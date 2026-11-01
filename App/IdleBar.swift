import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Barre du bas « au repos » : quand aucun pad n'a de réglages à montrer (rien de sélectionné, case vide, ou
/// verrouillé sans son lancé). Elle garde la hauteur de la vraie barre, pour que la grille ne bouge pas.
/// - Une bande d'invite en haut (avec le menu d'actions si une case vide est sélectionnée).
/// - En dessous, `IdleContent` : l'état du spectacle (grille en cours, contrôleur et sortie audio, LightKey)
///   et une astuce d'utilisation.
struct IdleBar: View {
    @Environment(ShowController.self) private var controller
    /// Case vide sélectionnée (déverrouillé) ; `nil` si rien n'est sélectionné ou si le spectacle est verrouillé.
    let emptyPosition: GridPosition?

    private static let stripHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            strip.frame(height: Self.stripHeight)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            IdleContent()
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.inspectorHeight, alignment: .topLeading)
        .background(Surface.panel)
    }

    @ViewBuilder
    private var strip: some View {
        HStack(spacing: 8) {
            if let position = emptyPosition {
                Icon.plus.view(size: 15)
                Text(hint(for: position))
                Spacer(minLength: 8)
                PadActionsMenu(position: position, hasPad: false)
            } else {
                Text(
                    controller.isLocked
                        ? "Spectacle verrouillé — cliquez sur un pad son pour afficher ses réglages de jeu."
                        : "Cliquez sur un pad pour voir et modifier ses réglages.")
                Spacer(minLength: 8)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Surface.textTertiary)
        .padding(.horizontal, 14)
    }

    private func hint(for position: GridPosition) -> String {
        if controller.currentGrid.columns[position.column].kind == .light {
            return "Ajoutez une commande lumière — LightKey apprend la note de ce pad sur le contrôleur."
        }
        return "Glissez un son de la bibliothèque ou du Finder sur ce pad."
    }
}

// MARK: - Contenu : état du spectacle + astuce

/// Les trois indicateurs et l'astuce du moment. Aussi affiché sous l'en-tête d'un pad lumière, qui n'a besoin
/// que d'une bande de réglages.
struct IdleContent: View {
    @Environment(ShowController.self) private var controller
    /// Astuce affichée. Elle avance à chaque fois que l'écran disparaît : à chaque retour, une astuce différente.
    @AppStorage("idleTipCursor") private var cursor = 0

    private static let spacing: CGFloat = 12

    var body: some View {
        let tips = Tips.visible(locked: controller.isLocked)
        let index = tips.isEmpty ? 0 : ((cursor % tips.count) + tips.count) % tips.count
        GeometryReader { proxy in
            let total = max(proxy.size.width - Self.spacing, 0)
            HStack(spacing: Self.spacing) {
                HStack(spacing: Self.spacing) {
                    ForEach(cards) { card in StatusCard(card: card) }
                }
                .frame(width: total * 0.58)
                if !tips.isEmpty {
                    TipCard(
                        tip: tips[index], position: index + 1, count: tips.count,
                        previous: { cursor -= 1 }, next: { cursor += 1 }
                    )
                    .frame(width: total * 0.42)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onDisappear { cursor += 1 }
    }

    // MARK: Indicateurs

    private var cards: [StatusCardModel] {
        [gridCard, controllerCard, lightingCard]
    }

    private var gridCard: StatusCardModel {
        let stats = gridStats
        let playing = playingCount
        return StatusCardModel(
            id: "grille", icon: .wave, title: "Grille en cours", headline: controller.currentGrid.name,
            lines: [
                .init(text: stats.sounds == 0 ? "Aucun son" : stats.sounds == 1 ? "1 son" : "\(stats.sounds) sons", tone: .neutral),
                .init(
                    text: playing == 0 ? "Rien en lecture" : playing == 1 ? "1 pad en lecture" : "\(playing) pads en lecture",
                    tone: playing == 0 ? .neutral : .active),
            ])
    }

    private var controllerCard: StatusCardModel {
        let connected = controller.connectedControllerName
        let output: StatusCardModel.Line
        if let uid = controller.selectedOutputUID {
            if let device = controller.outputDevices.first(where: { $0.uid == uid }) {
                output = .init(text: "Sortie : \(device.name)", tone: .ok)
            } else {
                output = .init(text: "Sortie débranchée", tone: .warning)
            }
        } else {
            output = .init(text: "Sortie : par défaut du Mac", tone: .ok)
        }
        return StatusCardModel(
            id: "controleur", icon: .volume, title: "Contrôleur et audio", headline: connected ?? "Aucun contrôleur",
            lines: [
                connected == nil
                    ? .init(text: "Branchez un Launchpad ou un APC mini mk2", tone: .neutral)
                    : .init(text: "Branché", tone: .ok),
                output,
            ])
    }

    private var lightingCard: StatusCardModel {
        let lights = gridStats.lights
        return StatusCardModel(
            id: "lumiere", icon: .spotlight, title: "Éclairage", headline: "LightKey",
            lines: [
                .init(text: "Port « Lalabob Lumière » actif", tone: .ok),
                .init(
                    text: lights == 0 ? "Aucune commande lumière" : lights == 1 ? "1 commande lumière" : "\(lights) commandes lumière",
                    tone: .neutral),
            ])
    }

    private var gridStats: (sounds: Int, lights: Int) {
        var sounds = 0
        var lights = 0
        for column in controller.currentGrid.columns {
            for case let pad? in column.slots {
                switch pad.content {
                case .audio: sounds += 1
                case .light: lights += 1
                }
            }
        }
        return (sounds, lights)
    }

    private var playingCount: Int {
        controller.playback.values.filter { event in
            if case .playing = event.state { true } else { false }
        }.count
    }
}

// MARK: - Carte d'indicateur

private struct StatusCardModel: Identifiable {
    enum Tone {
        case ok, active, neutral, warning

        var dot: Color {
            switch self {
            case .ok: .green
            case .active: Surface.lightAccent
            case .neutral: Surface.textTertiary
            case .warning: .orange
            }
        }

        var glows: Bool { self == .ok || self == .active }
    }

    struct Line: Identifiable {
        let text: String
        let tone: Tone
        var id: String { text }
    }

    let id: String
    let icon: Icon
    let title: String
    let headline: String
    let lines: [Line]
}

private struct StatusCard: View {
    let card: StatusCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                card.icon.view(size: 13)
                Text(card.title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .lineLimit(1)
            }
            .foregroundStyle(Surface.textTertiary)
            Text(card.headline)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Surface.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(card.lines) { line in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(line.tone.dot)
                            .frame(width: 7, height: 7)
                            .shadow(color: line.tone.glows ? line.tone.dot.opacity(0.8) : .clear, radius: 4)
                            .accessibilityHidden(true)
                        Text(line.text)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Surface.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Surface.well, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Carte d'astuce

private struct TipCard: View {
    let tip: Tip
    let position: Int
    let count: Int
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Surface.lightAccent.opacity(0.12))
                .frame(width: 52, height: 52)
                .overlay { Icon.lightbulb.view(size: 26).foregroundStyle(Surface.lightAccent) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("ASTUCE \(position) / \(count)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Surface.lightAccent)
                    Spacer(minLength: 4)
                    ForEach(tip.keys, id: \.self) { KeyCap(label: $0) }
                }
                Text(tip.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Surface.textPrimary)
                    .lineLimit(2)
                Text(tip.text)
                    .font(.system(size: 12))
                    .foregroundStyle(Surface.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 6) {
                TipNavButton(forward: false, label: "Astuce précédente", action: previous)
                TipNavButton(forward: true, label: "Astuce suivante", action: next)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Surface.well, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05)))
    }
}

/// Un raccourci montré comme une petite touche de clavier.
private struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Surface.textPrimary)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1)))
    }
}

private struct TipNavButton: View {
    let forward: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TipArrow()
                .stroke(Surface.textSecondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 5, height: 9)
                .scaleEffect(x: forward ? 1 : -1)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 14)
        .interactiveCursor(.link)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Chevron « > » ; retourné pour « < ».
private nonisolated struct TipArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}
