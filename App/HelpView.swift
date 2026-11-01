import LalabobDesign
import SwiftUI

/// Fenêtre d'aide (menu Aide ▸ Aide de Lalabob, ⌘?) : les rubriques à gauche, le texte à droite, une recherche en haut.
struct HelpView: View {
    @State private var query = ""
    @State private var selection: HelpTopic.ID? = HelpContent.topics.first?.id

    private var visibleTopics: [HelpTopic] { HelpContent.topics(matching: query) }

    var body: some View {
        NavigationSplitView {
            List(visibleTopics, selection: $selection) { topic in
                Label {
                    Text(topic.title)
                } icon: {
                    topic.symbol.view(size: 15)
                }
                .tag(topic.id)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .overlay {
                if visibleTopics.isEmpty {
                    Text("Aucun résultat pour « \(query) »")
                        .font(.callout)
                        .foregroundStyle(Surface.textSecondary)
                }
            }
        } detail: {
            if let topic = visibleTopics.first(where: { $0.id == selection }) ?? visibleTopics.first {
                ScrollView {
                    HelpTopicView(topic: topic)
                        .frame(maxWidth: 640, alignment: .leading)
                        .padding(28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(topic.id)
            } else {
                Color.clear
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Rechercher dans l'aide")
        .frame(minWidth: 760, minHeight: 520)
        .background(Surface.window)
        .preferredColorScheme(.dark)
        .navigationTitle("Aide de Lalabob")
    }
}

/// Une rubrique : son titre, puis ses blocs.
private struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(topic.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Surface.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                HelpBlockView(block: block)
            }
        }
    }
}

private struct HelpBlockView: View {
    let block: HelpBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            markdown(text)
                .font(.system(size: 14))
                .foregroundStyle(Surface.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .steps(let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .frame(width: 22, height: 22)
                            .background(Surface.lightAccent.opacity(0.2), in: .circle)
                            .foregroundStyle(Surface.lightAccent)
                            .accessibilityHidden(true)
                        markdown(item)
                            .font(.system(size: 14))
                            .foregroundStyle(Surface.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•").foregroundStyle(Surface.textTertiary).accessibilityHidden(true)
                        markdown(item)
                            .font(.system(size: 14))
                            .foregroundStyle(Surface.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .shortcuts(let rows):
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(row.keys)
                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Surface.panel, in: .rect(cornerRadius: 6))
                            .foregroundStyle(Surface.textPrimary)
                            .frame(width: 130, alignment: .leading)
                        Text(row.effect)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Surface.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 7)
                    .accessibilityElement(children: .combine)
                    if index < rows.count - 1 { Divider().overlay(Color.white.opacity(0.06)) }
                }
            }
        case .warning(let text):
            HStack(alignment: .top, spacing: 10) {
                Icon.warning.view(size: 16).foregroundStyle(Surface.lightAccent)
                markdown(text)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Surface.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Surface.lightAccent.opacity(0.1), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Surface.lightAccent.opacity(0.25)))
        }
    }

    /// Markdown en ligne (gras, italique, code) ; le texte brut si l'analyse échoue.
    private func markdown(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) { return Text(attributed) }
        return Text(text)
    }
}

#Preview("Aide") {
    Fonts.register()
    return HelpView().frame(width: 900, height: 640)
}
