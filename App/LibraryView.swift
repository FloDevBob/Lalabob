import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Bibliothèque : recherche, dossiers favoris, sons du dossier choisi (glisser vers un pad).
struct LibraryView: View {
    @Environment(LibraryController.self) private var library
    @Environment(ShowController.self) private var controller
    @State private var choosingFolder = false

    var body: some View {
        @Bindable var library = library
        VStack(alignment: .leading, spacing: 12) {
            TextField("Rechercher", text: $library.query)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Favoris").font(.system(size: 11, weight: .semibold)).foregroundStyle(Surface.textTertiary)
                Spacer()
                Button("Ajouter un dossier", systemImage: "plus") { choosingFolder = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Ajouter un dossier de sons")
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(library.favorites) { favorite in
                    favoriteRow(favorite)
                }
                if library.favorites.isEmpty {
                    Text("Ajoutez un dossier de sons avec +.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Surface.textTertiary)
                }
            }

            Divider().overlay(Color.white.opacity(0.06))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(library.visibleItems) { item in
                        itemRow(item)
                    }
                }
            }

            Text("Glissez un son sur un pad")
                .font(.system(size: 11.5))
                .foregroundStyle(Surface.textTertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(Surface.chrome)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { Task { await library.addFavorite(url) } }
        }
        .task {
            if library.currentFavorite == nil, let first = library.favorites.first { await library.select(first.id) }
        }
    }

    private func favoriteRow(_ favorite: LibraryController.Favorite) -> some View {
        let isCurrent = library.currentFavorite == favorite.id
        return Button {
            Task { await library.select(favorite.id) }
        } label: {
            Label(favorite.name, systemImage: "folder.fill")
                .font(.system(size: 12.5))
                .foregroundStyle(isCurrent ? Surface.textPrimary : Surface.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isCurrent ? Surface.panel : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Retirer des favoris", role: .destructive) { library.removeFavorite(favorite.id) }
        }
    }

    private func itemRow(_ item: AudioLibraryItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(Surface.lightAccent.opacity(0.8))
            Text(item.name)
                .font(.system(size: 12.5))
                .foregroundStyle(Surface.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if controller.usesAudioFile(named: item.name) {
                Circle().fill(Tint.turquoise.vividColor).frame(width: 6, height: 6)
                    .accessibilityLabel("Déjà sur la grille")
            }
            Text(item.duration.map(AudioLibrary.formatDuration) ?? "—")
                .font(Typography.mono)
                .foregroundStyle(Surface.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(.rect)
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .accessibilityElement(children: .combine)
    }
}
