import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Bibliothèque : recherche, dossiers favoris, sons du dossier choisi (glisser vers un pad).
struct LibraryView: View {
    @Environment(LibraryController.self) private var library
    @Environment(ShowController.self) private var controller
    @Environment(PreviewController.self) private var preview
    @State private var choosingFolder = false
    @State private var previewWaveform: Waveform?

    var body: some View {
        @Bindable var library = library
        VStack(alignment: .leading, spacing: 12) {
            TextField("Rechercher", text: $library.query)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Favoris").font(.system(size: 11, weight: .semibold)).foregroundStyle(Surface.textTertiary)
                Spacer()
                Button("Ajouter un dossier", icon: .plus) { choosingFolder = true }
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

            previewZone
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

    /// Pré-écoute du son sélectionné : bouton lecture, titre, mini forme d'onde avec avancement.
    private var previewZone: some View {
        let item = library.items.first { $0.id == library.selectedItem }
        let isPlaying = item.map { preview.playingItem == $0.id } ?? false
        return HStack(spacing: 10) {
            Button {
                if let item { togglePreview(item) }
            } label: {
                (isPlaying ? Icon.stop : Icon.play).view(size: 16)
                    .frame(width: 34, height: 34)
                    .background(item == nil ? Surface.well : Surface.lightAccent, in: .circle)
                    .foregroundStyle(item == nil ? Surface.textTertiary : Surface.window)
            }
            .buttonStyle(.plain)
            .disabled(item == nil)
            .help(isPlaying ? "Arrêter la pré-écoute" : "Pré-écouter")
            .accessibilityLabel(isPlaying ? "Arrêter la pré-écoute" : "Pré-écouter")

            VStack(alignment: .leading, spacing: 4) {
                Text(item?.name ?? "Sélectionnez un son")
                    .font(.system(size: 12))
                    .foregroundStyle(item == nil ? Surface.textTertiary : Surface.textPrimary)
                    .lineLimit(1)
                miniWave(progress: isPlaying ? preview.progress : 0)
            }
        }
        .padding(10)
        .background(Surface.panel, in: .rect(cornerRadius: 12))
        .task(id: library.selectedItem) {
            previewWaveform = nil
            guard let item else { return }
            previewWaveform = try? await WaveformStore.shared.waveform(for: item.url, buckets: 80)
        }
        .task(id: preview.playingItem) {
            while preview.playingItem != nil, !Task.isCancelled {
                preview.refreshProgress()
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
        .onChange(of: controller.isLocked) { if controller.isLocked { preview.stop() } }
        .alert("Pré-écoute impossible", isPresented: Binding(get: { preview.error != nil }, set: { if !$0 { preview.dismissError() } })) {
            Button("OK") { preview.dismissError() }
        } message: {
            Text(preview.error ?? "")
        }
    }

    private func miniWave(progress: Double) -> some View {
        Canvas { context, size in
            guard let peaks = previewWaveform?.peaks, !peaks.isEmpty else {
                context.fill(Path(CGRect(x: 0, y: size.height / 2 - 0.5, width: size.width, height: 1)), with: .color(Surface.textTertiary.opacity(0.4)))
                return
            }
            let barWidth = size.width / CGFloat(peaks.count)
            for (index, peak) in peaks.enumerated() {
                let half = max(CGFloat(min(peak, 1)) * size.height / 2, 0.5)
                let played = Double(index) / Double(peaks.count) < progress
                context.fill(
                    Path(CGRect(x: CGFloat(index) * barWidth, y: size.height / 2 - half, width: max(barWidth - 0.6, 0.5), height: half * 2)),
                    with: .color(played ? Surface.lightAccent : Surface.textTertiary.opacity(0.7)))
            }
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }

    private func togglePreview(_ item: AudioLibraryItem) {
        preview.toggle(item, deviceUID: controller.selectedOutputUID, isLocked: controller.isLocked)
    }

    private func favoriteRow(_ favorite: LibraryController.Favorite) -> some View {
        let isCurrent = library.currentFavorite == favorite.id
        return Button {
            Task { await library.select(favorite.id) }
        } label: {
            Label { Text(favorite.name) } icon: { Icon.folder.view(size: 15) }
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
        let isSelected = library.selectedItem == item.id
        return HStack(spacing: 8) {
            Icon.wave.view(size: 15)
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
        .background(isSelected ? Surface.panel : .clear, in: .rect(cornerRadius: 8))
        .overlay {
            if isSelected { RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.18)) }
        }
        .contentShape(.rect)
        .onTapGesture(count: 2) {
            library.selectItem(item.id)
            togglePreview(item)
        }
        .onTapGesture { library.selectItem(item.id) }
        .onDrag {
            library.selectItem(item.id)
            return NSItemProvider(object: item.url as NSURL)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
