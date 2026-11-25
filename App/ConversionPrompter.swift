import LalabobDesign
import LalabobEngine
import LalabobModel
import Observation
import SwiftUI

extension ColumnKind {
    /// Nom affiché d'un type de colonne.
    var title: String {
        switch self {
        case .audio: "Son"
        case .mixed: "Son et lumière"
        case .light: "Lumière"
        }
    }

    /// Ce que le type permet, en une ligne (popover du type de colonne).
    var explanation: String {
        switch self {
        case .audio: "Sons uniquement · fader de volume, filtre, stop"
        case .mixed: "Pads son, lumière, ou les deux à la fois · fader de volume"
        case .light: "Cues uniquement · fader MIDI vers LightKey (intensité)"
        }
    }
}

extension PadKind {
    /// Nom affiché d'un type de pad.
    var title: String {
        switch self {
        case .audio: "Son"
        case .light: "Lumière"
        case .mixed: "Les deux"
        }
    }
}

/// Une confirmation en attente avant une conversion qui retire quelque chose (fiche 07). Rien n'est modifié tant que
/// l'utilisateur n'a pas confirmé ; un plan sans perte s'applique tout de suite.
@MainActor
@Observable
final class ConversionPrompter {
    struct Line: Identifiable {
        enum Tone { case removed, reduced, kept }
        let id = UUID()
        let tone: Tone
        let headline: String
        let detail: String?
    }

    struct Alternative {
        let label: String
        let apply: @MainActor () -> Void
    }

    struct Pending: Identifiable {
        let id = UUID()
        let title: String
        let lines: [Line]
        let footer: String
        let confirmLabel: String
        let alternative: Alternative?
        let apply: @MainActor () -> Void
    }

    /// La confirmation affichée (feuille), `nil` s'il n'y en a pas.
    var pending: Pending?

    // MARK: Colonnes

    /// Demande de changer le type d'une colonne : appliquée tout de suite si rien n'est perdu, sinon confirmée d'abord.
    /// Un changement impossible (colonnes lumière communes) ou refusé verrouillé se signale par les messages habituels.
    func requestColumnKind(_ column: Int, to kind: ColumnKind, controller: ShowController) {
        guard !controller.isLocked else { return controller.notifyLocked() }
        guard controller.currentGrid.columns[column].kind != kind else { return }
        guard controller.columnKindProblem(column, to: kind) == nil else {
            controller.setColumnKind(column, to: kind)  // pose le message expliquant le refus
            return
        }
        let plan = controller.conversionPlan(column: column, to: kind)
        guard !plan.isLossless else {
            controller.setColumnKind(column, to: kind)
            return
        }
        let current = controller.currentGrid.columns[column]
        let name = current.name
        // Son ↔ Lumière : « Son et lumière » ne retire rien, on le propose à la place.
        var alternative: Alternative?
        if current.kind != .mixed, kind != .mixed,
            controller.conversionPlan(column: column, to: .mixed).isLossless
        {
            alternative = Alternative(label: "Passer en « Son et lumière »") { [weak controller] in
                controller?.setColumnKind(column, to: .mixed)
            }
        }
        pending = Pending(
            title: "Passer « \(name) » en colonne \(kind.title) ?",
            lines: Self.lines(for: plan, keptPads: current.slots.compactMap { $0 }.count - plan.affectedPadCount),
            footer: Self.footer(for: plan, controller: controller),
            confirmLabel: "Convertir",
            alternative: alternative,
            apply: { [weak controller] in controller?.setColumnKind(column, to: kind) })
    }

    /// Vider une colonne : demande confirmation s'il y a des pads.
    func requestClearColumn(_ column: Int, controller: ShowController) {
        guard !controller.isLocked else { return controller.notifyLocked() }
        let pads = controller.currentGrid.columns[column].slots.compactMap { $0 }
        guard !pads.isEmpty else { return }
        var plan = ConversionPlan()
        plan.deletedPads = pads
        pending = Pending(
            title: "Vider « \(controller.currentGrid.columns[column].name) » ?",
            lines: Self.lines(for: plan, keptPads: 0),
            footer: Self.footer(for: plan, controller: controller),
            confirmLabel: "Vider",
            alternative: nil,
            apply: { [weak controller] in controller?.clearColumn(column) })
    }

    // MARK: Pads

    /// Demande de changer le type d'un pad (colonne mixte) : même principe.
    func requestPadKind(at position: GridPosition, to kind: PadKind, controller: ShowController) {
        guard !controller.isLocked else { return controller.notifyLocked() }
        guard let pad = controller.pad(at: position), pad.kind != kind else { return }
        guard controller.currentGrid.columns[position.column].kind == .mixed else {
            controller.setPadKind(at: position, to: kind)  // pose le message : la colonne n'accepte qu'un type
            return
        }
        let plan = controller.conversionPlan(padAt: position, to: kind)
        guard !plan.isLossless else {
            controller.setPadKind(at: position, to: kind)
            return
        }
        pending = Pending(
            title: "Passer « \(pad.title) » en pad \(kind.title.lowercased()) ?",
            lines: Self.lines(for: plan, keptPads: 0),
            footer: Self.footer(for: plan, controller: controller),
            confirmLabel: "Convertir",
            alternative: nil,
            apply: { [weak controller] in controller?.setPadKind(at: position, to: kind) })
    }

    // MARK: Textes

    private static func plural(_ count: Int, _ one: String, _ many: String) -> String { count == 1 ? one : many }

    private static func titles(_ pads: [Pad]) -> String {
        let shown = pads.prefix(5).map(\.title).joined(separator: ", ")
        return pads.count > 5 ? shown + "…" : shown
    }

    static func lines(for plan: ConversionPlan, keptPads: Int) -> [Line] {
        var lines: [Line] = []
        if !plan.deletedPads.isEmpty {
            let n = plan.deletedPads.count
            lines.append(Line(
                tone: .removed, headline: "\(n) \(plural(n, "pad sera supprimé", "pads seront supprimés"))",
                detail: titles(plan.deletedPads)))
        }
        if !plan.padsLosingLight.isEmpty {
            let n = plan.padsLosingLight.count
            lines.append(Line(
                tone: .reduced, headline: "\(n) \(plural(n, "pad perdra sa cue", "pads perdront leur cue"))",
                detail: titles(plan.padsLosingLight) + " · l'appairage est oublié (rien n'est changé dans LightKey)"))
        }
        if !plan.padsLosingSound.isEmpty {
            let n = plan.padsLosingSound.count
            lines.append(Line(
                tone: .reduced, headline: "\(n) \(plural(n, "pad perdra son son", "pads perdront leur son")) et ses réglages",
                detail: titles(plan.padsLosingSound)))
        }
        if plan.faderPairingForgotten {
            lines.append(Line(tone: .reduced, headline: "L'appairage du fader est oublié", detail: "Rien n'est changé dans LightKey."))
        }
        if plan.filterReset {
            lines.append(Line(tone: .reduced, headline: "Le filtre revient au neutre", detail: nil))
        }
        if keptPads > 0 {
            lines.append(Line(
                tone: .kept, headline: "\(keptPads) \(plural(keptPads, "pad reste tel quel", "pads restent tels quels"))", detail: nil))
        }
        return lines
    }

    /// « Annulable avec ⌘Z. » + ce qu'il advient des sons en cours : seuls ceux des pads qui perdent leur son s'arrêtent.
    static func footer(for plan: ConversionPlan, controller: ShowController) -> String {
        let silenced = (plan.deletedPads + plan.padsLosingSound).filter { controller.playback[$0.id]?.state.isActive == true }
        let sounds =
            silenced.isEmpty
            ? "Aucun son en cours n'est arrêté."
            : "Le son en cours de \(titles(silenced)) s'arrête net ; les autres sons continuent."
        return "Annulable avec ⌘Z. " + sounds
    }
}

/// La feuille de confirmation : ce qui disparaît, nommé et chiffré, avec une sortie sans perte quand elle existe.
struct ConversionSheet: View {
    let pending: ConversionPrompter.Pending
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(pending.title)
                .font(.system(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(pending.lines) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(color(line.tone)).frame(width: 8, height: 8).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.headline).font(.system(size: 12.5, weight: .semibold))
                            if let detail = line.detail {
                                Text(detail).font(.system(size: 12)).foregroundStyle(Surface.textSecondary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Text(pending.footer)
                .font(.system(size: 11.5))
                .foregroundStyle(Surface.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Annuler", action: close)
                    .keyboardShortcut(.cancelAction)
                if let alternative = pending.alternative {
                    Button(alternative.label) {
                        close()
                        alternative.apply()
                    }
                }
                Button(pending.confirmLabel) {
                    close()
                    pending.apply()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private func color(_ tone: ConversionPrompter.Line.Tone) -> Color {
        switch tone {
        case .removed: Color(red: 1, green: 0.36, blue: 0.4)
        case .reduced: Surface.lightAccent
        case .kept: Surface.loopAccent
        }
    }
}
