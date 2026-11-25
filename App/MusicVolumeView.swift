import LalabobDesign
import LalabobEngine
import SwiftUI

/// Pastille « Apple Music 62 % » de l'en-tête (APC mini mk2 branché) : le 9e fader règle le volume d'Apple Music.
/// États : actif (rose), « fermé » (Music n'est pas lancé : rien n'est envoyé), « à autoriser » (macOS a refusé), désactivé (gris).
struct MusicVolumePill: View {
    let session: ControllerSession
    @State private var shown = false

    private static let pink = Color(red: 1, green: 0.35, blue: 0.55)

    private var tint: Color { session.isMusicVolumeEnabled && session.musicStatus != .notAuthorized ? Self.pink : Surface.textTertiary }

    private var summary: String {
        guard session.isMusicVolumeEnabled else { return "désactivé" }
        switch session.musicStatus {
        case .notAuthorized: return "à autoriser"
        case .notRunning: return session.musicVolume.map { "\($0) %" } ?? "fermé"
        case .running: return session.musicVolume.map { "\($0) %" } ?? "prêt"
        }
    }

    var body: some View {
        Button { shown.toggle() } label: {
            HStack(spacing: 6) {
                Icon.music.view(size: 14).foregroundStyle(tint)
                Text("Apple Music").font(.system(size: 12)).foregroundStyle(Surface.textSecondary)
                Text(summary).font(.system(size: 12, design: .monospaced)).foregroundStyle(tint)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .interactiveCursor(.link)
        .popover(isPresented: $shown, arrowEdge: .bottom) { MusicVolumePopover(session: session) }
        .help("Le 9e fader de l'APC règle le volume d'Apple Music — cliquer pour les réglages")
        .accessibilityLabel("Volume d'Apple Music, \(summary)")
    }
}

struct MusicVolumePopover: View {
    let session: ControllerSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                "Piloter le volume d'Apple Music",
                isOn: Binding(get: { session.isMusicVolumeEnabled }, set: { session.setMusicVolumeEnabled($0) })
            )
            .toggleStyle(.switch)
            .font(.system(size: 13, weight: .semibold))

            if let volume = session.musicVolume {
                ProgressView(value: Double(volume), total: 100) { Text("Volume actuel : \(volume) %").font(.system(size: 12)) }
            }
            switch session.musicStatus {
            case .notAuthorized:
                Text("macOS a refusé l'accès. Autorisez Lalabob à contrôler Music dans Réglages Système › Confidentialité et sécurité › Automatisation.")
                    .foregroundStyle(Surface.lightAccent)
            case .notRunning:
                Text("Apple Music n'est pas ouvert : rien n'est envoyé.").foregroundStyle(Surface.textSecondary)
            case .running:
                EmptyView()
            }
            Text("Ne touche que le volume d'Apple Music. N'ouvre jamais Music. Désactivez ceci si un autre logiciel s'en charge déjà.")
                .font(.system(size: 11.5))
                .foregroundStyle(Surface.textTertiary)
        }
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(width: 320)
    }
}
