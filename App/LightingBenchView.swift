import AppKit
import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Banc d'essai de l'appairage lumière : pour vérifier, sans toucher au spectacle, que le contrôleur, Lalabob
/// et LightKey se parlent (étape 0 du plan J7).
struct LightingBenchView: View {
    let session: ControllerSession?

    var body: some View {
        Group {
            if let session {
                BenchContent(bench: session.bench)
                    .onAppear { session.start() }
            } else {
                Text("CoreMIDI n'est pas disponible : le banc d'essai ne peut pas démarrer.")
                    .foregroundStyle(Surface.textSecondary)
            }
        }
        .frame(minWidth: 980, minHeight: 600)
        .background(Surface.window)
        .preferredColorScheme(.dark)
    }
}

private struct BenchContent: View {
    @Bindable var bench: LightingTestBench

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                status
                guide
                BenchGrid(bench: bench)
                options
            }
            .frame(width: 430)
            Journal(bench: bench)
        }
        .padding(20)
        .onAppear { bench.isOpen = true }
        .onDisappear { bench.isOpen = false }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusRow(
                ok: bench.isControllerConnected,
                title: bench.isControllerConnected ? "Contrôleur : \(bench.controllerName)" : "Contrôleur : aucun branché",
                detail: bench.isControllerConnected ? nil : "Les notes de l'\(bench.controllerName) sont utilisées.")
            StatusRow(ok: true, title: "Port créé : « Lalabob Lumière » (Lalabob → LightKey)", detail: nil)
            StatusRow(
                ok: bench.feedbackCount > 0,
                title: bench.feedbackCount > 0
                    ? "Retour de LightKey reçu (\(bench.feedbackCount) messages)" : "Retour de LightKey : rien reçu pour l'instant",
                detail: bench.feedbackCount > 0 ? nil : "Port « Lalabob Retour Lumière » (LightKey → Lalabob)")
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Comment essayer").font(.headline)
            Text("1. Dans LightKey, réglages MIDI : entrée « Lalabob Lumière », retour (Send Feedback To) « Lalabob Retour Lumière ».")
            Text("2. Dans LightKey : clic droit sur une cue › External Control › Add Trigger…")
            Text("3. Cliquez une case ci-dessous (ou appuyez sur un pad, option cochée) : LightKey apprend la note.")
            Text("4. Relancez la cue : le journal montre ce que LightKey répond.")
        }
        .font(.callout)
        .foregroundStyle(Surface.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Relayer vers LightKey les appuis du contrôleur sur les 2 colonnes de droite", isOn: $bench.relaysControllerPresses)
            Stepper(value: $bench.channel, in: 1...16) {
                Text("Canal envoyé à LightKey : \(bench.channel)")
            }
            Text("Si LightKey écoute aussi le contrôleur directement, une cue peut partir deux fois pendant l'essai.")
                .font(.caption)
                .foregroundStyle(Surface.textTertiary)
        }
    }
}

private struct StatusRow: View {
    let ok: Bool
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(ok ? Surface.loopAccent : Surface.textTertiary).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(Surface.textTertiary) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// La grille 8×8 du contrôleur, avec le numéro de note de chaque case.
private struct BenchGrid: View {
    let bench: LightingTestBench
    private let cell: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cliquez une case : Note On tant que le bouton est enfoncé").font(.caption).foregroundStyle(Surface.textTertiary)
            HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { column in
                    VStack(spacing: 4) {
                        ForEach(0..<8, id: \.self) { row in
                            BenchCell(bench: bench, position: GridPosition(column: column, row: row), size: cell)
                        }
                    }
                    .padding(.horizontal, column >= 6 ? 0 : 0)
                    .overlay(alignment: .top) {
                        if column >= 6 { Rectangle().fill(Surface.lightAccent.opacity(0.5)).frame(height: 2).offset(y: -4) }
                    }
                }
            }
        }
    }
}

private struct BenchCell: View {
    let bench: LightingTestBench
    let position: GridPosition
    let size: CGFloat

    var body: some View {
        let note = bench.note(at: position)
        let level = bench.lightKeyLevels[UInt8(note)] ?? 0
        let onScreen = bench.screenPressed.contains(position)
        let onController = bench.controllerPressed.contains(position)
        RoundedRectangle(cornerRadius: 8)
            .fill(onScreen ? Color.accentColor : Surface.panel)
            .overlay {
                if level > 0 { RoundedRectangle(cornerRadius: 8).fill(Surface.lightAccent.opacity(0.25 + 0.55 * Double(level) / 127)) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(onController ? Color.white : Surface.emptyPadStroke, lineWidth: onController ? 2 : 1)
            }
            .overlay {
                VStack(spacing: 0) {
                    Text("\(note)").font(.system(size: 11, weight: .semibold, design: .monospaced))
                    if level > 0 { Text("v\(level)").font(.system(size: 9, design: .monospaced)) }
                }
                .foregroundStyle(Surface.textPrimary)
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in bench.press(position) }
                    .onEnded { _ in bench.release(position) }
            )
            .help("Note \(note) · colonne \(position.column + 1), ligne \(position.row + 1)")
            .accessibilityLabel("Note \(note)")
            .accessibilityAddTraits(.isButton)
    }
}

private struct Journal: View {
    let bench: LightingTestBench

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Journal en direct").font(.headline)
                Spacer()
                Button("Copier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bench.transcript, forType: .string)
                }
                .disabled(bench.entries.isEmpty)
                Button("Effacer") { bench.clear() }.disabled(bench.entries.isEmpty)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(bench.entries) { entry in
                            JournalRow(entry: entry).id(entry.id)
                        }
                    }
                    .padding(10)
                }
                .background(Surface.well, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if bench.entries.isEmpty {
                        Text("Rien pour l'instant.\nAppuyez sur un pad ou cliquez une case.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Surface.textTertiary)
                    }
                }
                .onChange(of: bench.entries.last?.id) { _, last in
                    if let last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }
}

private struct JournalRow: View {
    let entry: LightingTestBench.Entry

    private var color: Color {
        switch entry.direction {
        case .fromController: Surface.textSecondary
        case .toLightKey: Color.accentColor
        case .fromLightKey: Surface.lightAccent
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.date, format: .dateTime.hour().minute().second())
                .foregroundStyle(Surface.textTertiary)
            Text(LightingTestBench.label(entry.direction))
                .foregroundStyle(color)
                .frame(width: 100, alignment: .leading)
            Text(entry.text).foregroundStyle(Surface.textPrimary)
        }
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
    }
}
