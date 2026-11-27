import LalabobDesign
import LalabobEngine
import SwiftUI

/// Banc d'essai DMX (Fenêtre ▸ Banc d'essai DMX) : un curseur par canal de la barre, pour vérifier le boîtier,
/// l'adresse et le tableau du manuel sans toucher au spectacle (J14, étape 1).
struct DMXBenchView: View {
    @Bindable var bench: DMXTestBench

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            status
            settings
            Divider()
            channels
            Text("Fermer la fenêtre arrête le signal : la barre garde sa dernière couleur. Cliquez Noir avant pour l'éteindre.")
                .font(.caption)
                .foregroundStyle(Surface.textTertiary)
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 640, alignment: .topLeading)
        .background(Surface.window)
        .preferredColorScheme(.dark)
        .onAppear { bench.open() }
        .onDisappear { Task { await bench.close() } }
    }

    private var status: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(bench.status.isConnected ? Surface.loopAccent : Surface.textTertiary).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                if let detail = statusDetail {
                    Text(detail).font(.caption).foregroundStyle(Surface.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        switch bench.status {
        case .stopped: "Signal arrêté"
        case .noDevice: "Aucun boîtier USB-DMX branché"
        case .connected(let port): "\(port.name) · signal envoyé"
        case .failed(let port, _): "\(port.name) · en erreur"
        }
    }

    private var statusDetail: String? {
        switch bench.status {
        case .noDevice: "Branchez le boîtier : Lalabob le cherche chaque seconde."
        case .failed(_, let message): "\(message). Nouvel essai chaque seconde (une autre app utilise-t-elle le boîtier ?)."
        default: nil
        }
    }

    private var settings: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Boîtier")
                HStack {
                    Picker("Boîtier", selection: $bench.selectedSerial) {
                        Text("Le premier branché").tag(String?.none)
                        ForEach(bench.ports) { port in
                            Text(port.name).tag(String?.some(port.serialNumber))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                    Button("Actualiser") { bench.refreshPorts() }
                }
            }
            GridRow {
                Text("Adresse")
                HStack {
                    Stepper(value: $bench.address, in: DMXTestBench.addressRange) {
                        Text("\(bench.address)").monospacedDigit()
                    }
                    Text("celle affichée par la barre (MENU → 15Ch → d …)")
                        .font(.caption)
                        .foregroundStyle(Surface.textTertiary)
                }
            }
            GridRow {
                Text("Essais")
                HStack {
                    Button("4 projecteurs en blanc") { bench.white() }
                    Button("Noir") { bench.black() }
                }
            }
        }
    }

    private var channels: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(DMXTestBench.channelNames.indices, id: \.self) { offset in
                    GridRow {
                        Text("\(bench.address + offset)")
                            .monospacedDigit()
                            .foregroundStyle(Surface.textTertiary)
                            .gridColumnAlignment(.trailing)
                        Text(DMXTestBench.channelNames[offset])
                        Slider(
                            value: Binding(
                                get: { Double(bench.values[offset]) },
                                set: { bench.setValue(UInt8($0.rounded()), at: offset) }),
                            in: 0...255
                        )
                        .frame(minWidth: 180)
                        .accessibilityLabel(DMXTestBench.channelNames[offset])
                        Text("\(bench.values[offset])")
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
    }
}
