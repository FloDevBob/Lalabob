import AppKit
import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Fenêtre d'accueil (spec `docs/spec-fenetre-accueil.md`, maquette « Version retenue ») : l'état du matériel, la visite
/// guidée et les spectacles récents. Elle remplace la fenêtre « Ouvrir » de macOS au lancement.
enum Welcome {
    static let windowID = "welcome"
    /// Préférence de ce Mac : afficher la fenêtre au lancement (vrai par défaut).
    static let showAtLaunchKey = "showWelcomeAtLaunch"
    static let size = CGSize(width: 960, height: 520)

    static var showsAtLaunch: Bool { UserDefaults.standard.object(forKey: showAtLaunchKey) as? Bool ?? true }

    /// Adresse du lien « ouvrez LightKey » (interceptée par la fenêtre, jamais ouverte telle quelle).
    static let openLightKeyURL = URL(string: "lalabob-welcome:open-lightkey")!

    /// Ferme la fenêtre d'accueil si elle est ouverte. Passe par AppKit : `dismissWindow` appelé depuis la fenêtre d'un
    /// document ne la ferme pas toujours (relevé le 28/11/2026, macOS 26).
    @MainActor
    static func close() {
        for window in NSApp.windows where window.identifier?.rawValue.hasPrefix(windowID) == true {
            window.close()
        }
    }

    static func openLightKey() {
        guard let url = HardwareProbe.lightKeyURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Mesures de la fenêtre (grille de 4 pt) : marges 24, écart 16, cartes 16, boutons 32 de haut.
private enum WelcomeMetrics {
    static let margin: CGFloat = 24
    static let gap: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 16
    static let buttonHeight: CGFloat = 32
    static let checklistWidth: CGFloat = 360
    static let headerHeight: CGFloat = 76
}

/// Un spectacle récent : son paquet, son nom, sa date, et l'aperçu une fois lu.
private struct RecentShow: Identifiable {
    let url: URL
    let name: String
    let date: Date?
    var preview: ShowThumbnail?
    var id: URL { url }
}

struct WelcomeView: View {
    @Environment(\.midiSession) private var midiSession
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openDocument) private var openDocument
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Welcome.showAtLaunchKey) private var showAtLaunch = true
    @State private var status: HardwareStatus?
    @State private var recents: [RecentShow] = []
    /// Hauteur de la barre de titre (masquée) : l'en-tête monte dessous, la fenêtre garde 520 pt en tout.
    @State private var titleBarHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: WelcomeMetrics.gap) {
                checklistCard
                    .frame(width: WelcomeMetrics.checklistWidth)
                    .frame(maxHeight: .infinity)
                VStack(spacing: WelcomeMetrics.gap) {
                    discoverCard
                    recentsCard.frame(maxHeight: .infinity)
                }
            }
            .padding(WelcomeMetrics.margin)
        }
        .frame(width: Welcome.size.width, height: Welcome.size.height)
        .background(Surface.window)
        .padding(.top, -titleBarHeight)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { titleBarHeight = $0 }
        .foregroundStyle(Surface.textPrimary)
        .environment(\.openURL, OpenURLAction { url in
            guard url == Welcome.openLightKeyURL else { return .systemAction }
            Welcome.openLightKey()
            return .handled
        })
        .task {
            // Un spectacle rouvert par macOS (restauration) : la fenêtre d'accueil n'a rien à faire là.
            if !NSDocumentController.shared.documents.isEmpty {
                Welcome.close()
                return
            }
            AppLifecycle.startSessions(midi: midiSession)
            AppLifecycle.openWelcome = { [openWindow] in openWindow(id: Welcome.windowID) }
            let session = midiSession
            let live = HardwareStatus(probe: .live(), controller: { session?.connectedModel })
            status = live
            live.start()
            await loadRecents()
        }
        .onDisappear { status?.stop() }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lalabob")
                    .font(.custom(Fonts.logoFamily, size: 26).weight(.semibold))
                Text("Régie son et lumière pour l'impro")
                    .font(.system(size: 13))
                    .foregroundStyle(Surface.textSecondary)
            }
            Spacer()
            Button {
                NSDocumentController.shared.openDocument(nil)
            } label: {
                WelcomeButtonLabel(title: "Ouvrir un spectacle…", shortcut: "⌘O")
            }
            .buttonStyle(WelcomeButtonStyle(kind: .secondary))
            Button {
                newDocument { LalabobDocument() }
            } label: {
                WelcomeButtonLabel(title: "Nouveau spectacle", shortcut: "⌘N")
            }
            .buttonStyle(WelcomeButtonStyle(kind: .primary))
        }
        // Les boutons de la fenêtre se posent à gauche de l'en-tête (titre masqué), comme dans la fenêtre principale.
        .padding(.leading, 88)
        .padding(.trailing, WelcomeMetrics.margin)
        .frame(height: WelcomeMetrics.headerHeight)
        .background(Surface.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
    }

    // MARK: Avant de jouer

    private var checklistCard: some View {
        let checklist = status?.checklist
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Avant de jouer").font(.system(size: 15, weight: .semibold))
                Spacer()
                if let checklist { StatusPill(text: checklist.summary, isReady: checklist.isAllReady) }
            }
            .frame(height: 20)
            .padding(.bottom, 8)
            if let checklist {
                ForEach(checklist.lines, id: \.device) { line in
                    Divider().overlay(.white.opacity(0.06))
                    ChecklistRow(line: line)
                }
            }
            Spacer(minLength: 0)
            Divider().overlay(.white.opacity(0.06))
            Toggle("Afficher cette fenêtre au lancement", isOn: $showAtLaunch)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .foregroundStyle(Surface.textSecondary)
                .padding(.top, 12)
        }
        .padding(WelcomeMetrics.cardPadding)
        .background(Surface.panel, in: .rect(cornerRadius: WelcomeMetrics.cardRadius))
    }

    // MARK: Découvrir Lalabob

    private var discoverCard: some View {
        let amber = Tint.ambre
        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Surface.lightAccent.opacity(0.2))
                .frame(width: 28, height: 28)
                .overlay { Icon.lightbulb.view(size: 16).foregroundStyle(Surface.lightAccent) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Découvrir Lalabob")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.top, 4)
                Text("Visite guidée en 5 chapitres, puis un spectacle d'entraînement pour essayer sans rien casser.")
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .opacity(0.92)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Commencer la visite") { openWindow(id: Tour.windowID) }
                        .buttonStyle(WelcomeButtonStyle(kind: .amber))
                    Button("Spectacle d'entraînement") {
                        Task { await Tour.openTrainingShow(with: openDocument) }
                    }
                    .buttonStyle(WelcomeButtonStyle(kind: .amberSecondary))
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(amber.labelColor)
        .padding(WelcomeMetrics.cardPadding)
        .background(amber.surfaceColor, in: .rect(cornerRadius: WelcomeMetrics.cardRadius))
    }

    // MARK: Spectacles récents

    private var recentsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Spectacles récents")
                .font(.system(size: 15, weight: .semibold))
                .frame(height: 20)
                .padding(.bottom, 8)
            if recents.isEmpty {
                Text("Vos spectacles apparaîtront ici.")
                    .font(.system(size: 13))
                    .foregroundStyle(Surface.textSecondary)
                    .padding(.top, 4)
            }
            ForEach(recents) { recent in
                Button {
                    Task {
                        do { _ = try await openDocument(at: recent.url) } catch { await loadRecents() }
                    }
                } label: {
                    RecentRow(recent: recent)
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 10)
                .interactiveCursor(.link)
                .help("Ouvrir « \(recent.name) »")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WelcomeMetrics.cardPadding)
        .background(Surface.panel, in: .rect(cornerRadius: WelcomeMetrics.cardRadius))
    }

    /// Les 3 derniers spectacles ouverts dont le paquet existe encore ; l'aperçu se lit en arrière-plan.
    private func loadRecents() async {
        let urls = NSDocumentController.shared.recentDocumentURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .prefix(3)
        recents = urls.map { url in
            RecentShow(
                url: url, name: url.deletingPathExtension().lastPathComponent,
                date: try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        }
        for url in urls {
            let preview = await Task.detached(priority: .utility) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return RecentShowPreview.load(packageURL: url)
            }.value
            if let index = recents.firstIndex(where: { $0.url == url }) { recents[index].preview = preview }
        }
    }
}

// MARK: - Éléments

/// Étiquette de statut, toujours en mots : vert si prêt, gris sinon. Le point n'est qu'une décoration.
private struct StatusPill: View {
    let text: String
    let isReady: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isReady ? Surface.loopAccent : Color(white: 0.42))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(isReady ? Surface.loopAccent : Surface.textSecondary)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(isReady ? Surface.loopAccent.opacity(0.13) : .white.opacity(0.07), in: .capsule)
        .fixedSize()
    }
}

/// Une ligne de « Avant de jouer » : icône, appareil et ce qui est détecté, statut ; dessous, la phrase.
private struct ChecklistRow: View {
    let line: WelcomeChecklist.Line

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Le statut se range à droite de l'appareil : le nom détecté garde toute la largeur (« Haut-parleurs MacBook Pro »).
            HStack(alignment: .center, spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(title.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Surface.textTertiary)
                        Spacer(minLength: 8)
                        StatusPill(text: line.status, isReady: line.isReady)
                    }
                    Text(line.detail)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(line.isReady ? Surface.textPrimary : Surface.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Text(hint)
                .font(.system(size: 12))
                .lineSpacing(1)
                .foregroundStyle(Surface.textSecondary)
                .tint(Surface.lightAccent)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 40)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch line.device {
        case .sound: "Son"
        case .controller: "Contrôleur"
        case .light: "Lumière"
        }
    }

    /// La phrase, avec le lien éventuel (« ouvrez LightKey ») souligné en ambre.
    private var hint: AttributedString {
        var text = AttributedString(line.hint)
        if let link = line.link {
            var linked = AttributedString(link)
            linked.link = Welcome.openLightKeyURL
            linked.underlineStyle = .single
            text += linked
        }
        text += AttributedString(line.hintEnd)
        return text
    }

    private var icon: some View {
        let (tint, glyph): (Tint, AnyView) =
            switch line.device {
            case .sound: (.turquoise, AnyView(Icon.volume.view(size: 16)))
            case .controller: (.vert, AnyView(ControllerGlyph()))
            case .light: (.ambre, AnyView(Icon.spotlight.view(size: 16)))
            }
        return RoundedRectangle(cornerRadius: 8)
            .fill(tint.surfaceColor)
            .frame(width: 28, height: 28)
            .overlay { glyph.foregroundStyle(tint.labelColor) }
            .accessibilityHidden(true)
    }
}

/// Le contrôleur : un carré et quatre pads, dans le style des icônes Iconoir.
private struct ControllerGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).stroke(lineWidth: 1.2).frame(width: 14, height: 14)
            Grid(horizontalSpacing: 2.5, verticalSpacing: 2.5) {
                GridRow {
                    RoundedRectangle(cornerRadius: 0.8).frame(width: 3, height: 3)
                    RoundedRectangle(cornerRadius: 0.8).frame(width: 3, height: 3).opacity(0.4)
                }
                GridRow {
                    RoundedRectangle(cornerRadius: 0.8).frame(width: 3, height: 3).opacity(0.4)
                    RoundedRectangle(cornerRadius: 0.8).frame(width: 3, height: 3)
                }
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// Une ligne de la liste des récents : vignette 40 pt, nom, résumé, date.
private struct RecentRow: View {
    let recent: RecentShow

    var body: some View {
        HStack(spacing: 12) {
            ShowThumbnailView(thumbnail: recent.preview)
            VStack(alignment: .leading, spacing: 0) {
                Text(recent.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(recent.preview?.summary ?? " ")
                    .font(.system(size: 12))
                    .foregroundStyle(Surface.textTertiary)
            }
            Spacer(minLength: 8)
            if let date = recent.date {
                Text(RecentShowPreview.dateLabel(for: date))
                    .font(.system(size: 12))
                    .foregroundStyle(Surface.textTertiary)
            }
        }
        .padding(8)
        .contentShape(.rect)
    }
}

/// Aperçu 8 × 8 de la première grille (40 pt). Sans aperçu (fichier illisible), un fond uni.
private struct ShowThumbnailView: View {
    let thumbnail: ShowThumbnail?

    var body: some View {
        Canvas { context, size in
            guard let thumbnail else { return }
            let count = CGFloat(8), gap: CGFloat = 1
            let cell = (size.width - gap * (count - 1)) / count
            for (index, value) in thumbnail.cells.enumerated() {
                let column = CGFloat(index / 8), row = CGFloat(index % 8)
                let rect = CGRect(x: column * (cell + gap), y: row * (cell + gap), width: cell, height: cell)
                let color: Color =
                    switch value {
                    case .empty: Surface.thumbnailEmpty
                    case .light: Tint.ambre.surfaceColor
                    case .tint(let tint): tint.surfaceColor
                    }
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
        .padding(4)
        .frame(width: 40, height: 40)
        .background(Surface.well, in: .rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

/// Texte et raccourci d'un bouton de l'en-tête.
private struct WelcomeButtonLabel: View {
    let title: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Text(shortcut).fontWeight(.regular).opacity(0.7)
        }
    }
}

/// Les boutons de la fenêtre : tous 32 pt de haut, rayon 8, texte 13 demi-gras.
private struct WelcomeButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, amber, amberSecondary }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(height: WelcomeMetrics.buttonHeight)
            .background(background, in: .rect(cornerRadius: 8))
            .overlay {
                if kind == .secondary { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1)) }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.rect(cornerRadius: 8))
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary: Surface.textPrimary
        case .amber: Color(red: 0x1A / 255, green: 0x14 / 255, blue: 0x06 / 255)
        case .amberSecondary: Tint.ambre.labelColor
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Surface.primaryAction
        case .secondary: Color(red: 0x1B / 255, green: 0x1D / 255, blue: 0x23 / 255)
        case .amber: Surface.lightAccent
        case .amberSecondary: .black.opacity(0.22)
        }
    }
}

#Preview("Fenêtre d'accueil") {
    WelcomeView()
        .preferredColorScheme(.dark)
}
