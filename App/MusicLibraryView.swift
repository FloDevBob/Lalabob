import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Panneau de gauche d'une grille Apple Music (déverrouillé) : état de Music, recherche, playlists en arbre, morceaux de la
/// playlist choisie (sélection multiple, glisser vers les pads), morceaux restés dans le nuage.
struct MusicLibraryView: View {
    @Environment(MusicLibraryController.self) private var library
    @Environment(ShowController.self) private var controller
    @Environment(PreviewController.self) private var preview
    @Environment(MusicPlaybackCoordinator.self) private var musicPlayer
    @State private var query = ""
    @State private var internetQuery = ""
    /// Le morceau dont l'extrait joue (ou se télécharge), et son fichier.
    @State private var previewing: (key: String, title: String, file: URL?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow
            if library.status == .running {
                Picker("Où chercher", selection: Binding(get: { library.source }, set: { library.source = $0 })) {
                    Text("Mes playlists").tag(MusicLibraryController.Source.library)
                    Text("Internet").tag(MusicLibraryController.Source.internet)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if library.status == .running, library.source == .internet {
                internetSection
            } else if library.status == .running {
                TextField("Rechercher une playlist ou un morceau", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .help("Filtre les playlists par nom et cherche les morceaux dans toute la bibliothèque de Music")
                    .task(id: query) {
                        try? await Task.sleep(for: .milliseconds(250))  // attendre la fin de la frappe
                        guard !Task.isCancelled else { return }
                        await library.setSearchText(query)
                    }
                playlistsSection
                Divider().overlay(Color.white.opacity(0.06))
                tracksSection
            } else {
                Spacer(minLength: 0)
            }
            Toggle(
                "Son de Music par Lalabob",
                isOn: Binding(get: { musicPlayer.isBridgeEnabled }, set: { musicPlayer.setBridgeEnabled($0) })
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.system(size: 11.5))
            .help("Le son de Music passe par Lalabob : fader, filtre et vumètre de la colonne, sortie choisie dans Lalabob, fondus sans à-coups. macOS demande l'autorisation d'enregistrement audio. Si la capture s'arrête, Music redevient audible tout seul.")
            if musicPlayer.isBridging {
                Text("Le son de Music passe par Lalabob (colonne du morceau).").font(.system(size: 11)).foregroundStyle(Surface.textTertiary)
            }
            if let problem = musicPlayer.bridgeProblem {
                Text(problem).font(.system(size: 11)).foregroundStyle(Surface.lightAccent).fixedSize(horizontal: false, vertical: true)
            }
            if let error = library.networkError {
                Text(error).font(.system(size: 11)).foregroundStyle(Surface.lightAccent).fixedSize(horizontal: false, vertical: true)
            }
            previewZone
        }
        .padding(14)
        .background(Surface.chrome)
        .task { await library.refresh() }
    }

    // MARK: État de Music

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 8) {
            Icon.music.view(size: 16).foregroundStyle(Surface.musicAccent)
            Text("Apple Music").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button("Actualiser", icon: .restart) { Task { await library.refresh() } }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Relire les playlists de Music")
        }
        switch library.status {
        case .running:
            EmptyView()
        case .notRunning:
            notice("Music n'est pas ouvert.") {
                Button("Ouvrir Music") {
                    Task {
                        await library.openMusic()
                        try? await Task.sleep(for: .seconds(2))
                        await library.refresh()
                    }
                }
            }
        case .notAuthorized:
            notice("macOS refuse à Lalabob l'accès à Music : Réglages Système › Confidentialité et sécurité › Automatisation.") {
                EmptyView()
            }
        case .failed(let message):
            notice("Music a répondu par une erreur : \(message)") { EmptyView() }
        }
    }

    private func notice(_ text: String, @ViewBuilder action: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.system(size: 12)).foregroundStyle(Surface.textSecondary).fixedSize(horizontal: false, vertical: true)
            action()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Surface.well, in: .rect(cornerRadius: 10))
    }

    // MARK: Playlists

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PLAYLISTS").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Surface.textTertiary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(library.visibleRows) { row in
                        playlistRow(row)
                    }
                    if library.visibleRows.isEmpty {
                        Text(query.isEmpty ? "Aucune playlist." : "Aucune playlist de ce nom.")
                            .font(.system(size: 11.5)).foregroundStyle(Surface.textTertiary)
                    }
                }
            }
            .frame(maxHeight: 190)
        }
    }

    private func playlistRow(_ row: MusicLibraryController.Row) -> some View {
        let playlist = row.playlist
        let isCurrent = playlist.id == library.selectedPlaylistID && query.isEmpty
        return Button {
            Task { await library.selectPlaylist(playlist.id) }
        } label: {
            HStack(spacing: 6) {
                if playlist.isFolder {
                    Text(library.expandedFolders.contains(playlist.id) ? "▾" : "▸")
                        .font(.system(size: 9)).foregroundStyle(Surface.textTertiary).frame(width: 10)
                    Icon.folder.view(size: 14).foregroundStyle(Surface.textSecondary)
                } else {
                    Spacer().frame(width: 10)
                    RoundedRectangle(cornerRadius: 3).fill(Surface.musicAccent.opacity(isCurrent ? 1 : 0.45)).frame(width: 12, height: 12)
                }
                Text(playlist.name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if !playlist.isFolder, playlist.trackCount > 0 {
                    Text("\(playlist.trackCount)").font(Typography.mono).foregroundStyle(Surface.textTertiary)
                }
            }
            .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
            .foregroundStyle(isCurrent ? Surface.textPrimary : Surface.textSecondary)
            .padding(.leading, CGFloat(row.depth) * 16)
            .padding(.horizontal, 6)
            .frame(height: 26)
            .background(isCurrent ? Color.white.opacity(0.08) : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 7, enabled: !isCurrent)
        .interactiveCursor(.link)
        .accessibilityLabel(playlist.isFolder ? "Dossier \(playlist.name)" : "Playlist \(playlist.name), \(playlist.trackCount) morceaux")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    // MARK: Morceaux

    private var tracksSection: some View {
        @Bindable var library = library
        let onGrid = Set(controller.show.grids.flatMap { $0.columns.flatMap { $0.slots.compactMap { $0?.music?.persistentID } } })
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text((query.isEmpty ? library.selectedPlaylist?.name ?? "" : "Résultats").uppercased())
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Surface.textTertiary).lineLimit(1)
                if query.isEmpty, library.cloudCount > 0 {
                    Text("· \(library.cloudCount) ☁").font(.system(size: 11)).foregroundStyle(Surface.lightAccent)
                        .help("\(library.cloudCount) morceau(x) dans le nuage : Internet nécessaire pour les jouer")
                }
                Spacer()
                if !library.selectedTrackIDs.isEmpty {
                    Text("\(library.selectedTrackIDs.count) sélectionné\(library.selectedTrackIDs.count > 1 ? "s" : "")")
                        .font(.system(size: 11)).foregroundStyle(Surface.musicAccent)
                }
            }
            HStack(spacing: 6) {
                Toggle("Téléchargés seulement", isOn: $library.onlyDownloaded)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("Masquer les morceaux restés dans le nuage")
                if query.isEmpty, library.cloudCount > 0 {
                    Button("Télécharger les \(library.cloudCount)") { Task { await library.downloadMissing() } }
                        .controlSize(.small)
                        .help("Demander à Music de télécharger les morceaux de cette playlist restés dans le nuage")
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(library.shownTracks) { track in
                        trackRow(track, onGrid: onGrid.contains(track.id))
                    }
                }
            }
            Text("Maj-clic : une plage · ⌘-clic : un de plus · glissez la sélection sur la grille")
                .font(.system(size: 11)).foregroundStyle(Surface.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func trackRow(_ track: MusicTrack, onGrid: Bool) -> some View {
        let isSelected = library.selectedTrackIDs.contains(track.id)
        return HStack(spacing: 7) {
            Circle().fill(onGrid ? Surface.musicAccent : .clear).frame(width: 6, height: 6)
                .help(onGrid ? "Déjà sur une grille" : "")
            (Text(track.title) + Text(track.artist.isEmpty ? "" : " · \(track.artist)").foregroundStyle(Surface.textTertiary))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if track.isDownloaded == false {
                Text("☁").foregroundStyle(Surface.lightAccent).help("Dans le nuage : Internet nécessaire pour le jouer")
            }
            previewButton(key: "lib-\(track.id)", title: track.title) { await library.previewFile(for: track) }
            Text(AudioLibrary.formatDuration(track.duration)).font(Typography.mono).foregroundStyle(Surface.textTertiary)
        }
        .font(.system(size: 12))
        .foregroundStyle(isSelected ? Surface.textPrimary : Surface.textSecondary)
        .padding(.horizontal, 7)
        .frame(height: 28)
        .background(isSelected ? Surface.musicAccent.opacity(0.22) : .clear, in: .rect(cornerRadius: 7))
        .contentShape(.rect)
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            library.clickTrack(track.id, extend: flags.contains(.shift), toggle: flags.contains(.command))
        }
        .onDrag {
            let tracks = library.dragged(from: track.id)
            controller.beginMusicDrag(count: tracks.count)
            return NSItemProvider(object: MusicDragToken.make(tracks) as NSString)
        }
        .interactiveCursor(.grabIdle)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title), \(track.artist), \(AudioLibrary.formatDuration(track.duration))"
            + (track.isDownloaded == false ? ", dans le nuage" : "") + (onGrid ? ", déjà sur une grille" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Sélectionner") { library.clickTrack(track.id) }
    }

    // MARK: Internet

    private var internetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Chercher sur Apple Music", text: $internetQuery)
                .textFieldStyle(.roundedBorder)
                .help("Cherche dans tout le catalogue d'Apple Music (internet nécessaire)")
                .task(id: internetQuery) {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    await library.searchInternet(internetQuery)
                }
            HStack {
                Text("CATALOGUE APPLE MUSIC").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Surface.textTertiary)
                Spacer()
                if library.isSearchingInternet { ProgressView().controlSize(.small) }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(library.internetResults) { track in
                        catalogRow(track)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Un morceau trouvé sur internet").font(.system(size: 12, weight: .semibold)).foregroundStyle(Surface.lightAccent)
                Text("« Ajouter… » ouvre le morceau dans Music : cliquez + pour l'ajouter à votre bibliothèque. Il apparaît alors dans « Mes playlists », prêt à glisser sur un pad.")
                    .font(.system(size: 11)).foregroundStyle(Surface.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Surface.lightAccent.opacity(0.1), in: .rect(cornerRadius: 10))
        }
    }

    private func catalogRow(_ track: CatalogTrack) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: track.artworkURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 5).fill(Surface.well)
            }
            .frame(width: 34, height: 34)
            .clipShape(.rect(cornerRadius: 5))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.system(size: 12)).lineLimit(1)
                Text("\(track.artist) · \(AudioLibrary.formatDuration(track.duration))")
                    .font(.system(size: 11)).foregroundStyle(Surface.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            previewButton(key: "cat-\(track.id)", title: track.title) { await library.previewFile(for: track) }
            Button("Ajouter…") { Task { await library.openInMusic(track) } }
                .controlSize(.small)
                .disabled(track.storeURL == nil)
                .help("Ouvre ce morceau dans Music : cliquez + pour l'ajouter à votre bibliothèque")
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(track.title), \(track.artist)")
    }

    // MARK: Extraits de 30 s

    /// Bouton ▶ / ■ d'un extrait de 30 s (téléchargé à la première écoute), joué par la pré-écoute de Lalabob : Music n'est pas touché.
    private func previewButton(key: String, title: String, file: @escaping () async -> URL?) -> some View {
        let isThis = previewing?.key == key && (previewing?.file == nil || preview.playingItem == previewing?.file)
        return Button {
            if isThis {
                preview.stop()
                previewing = nil
                return
            }
            preview.stop()
            previewing = (key, title, nil)
            Task {
                guard let url = await file(), previewing?.key == key else {
                    if previewing?.key == key { previewing = nil }
                    return
                }
                previewing = (key, title, url)
                preview.toggle(
                    AudioLibraryItem(url: url, name: title, duration: 30), deviceUID: controller.selectedOutputUID,
                    isLocked: controller.isLocked)
            }
        } label: {
            (isThis ? Icon.stopFill : Icon.playFill).view(size: 9)
                .frame(width: 20, height: 20)
                .background(Surface.musicAccent.opacity(isThis ? 1 : 0.25), in: .circle)
                .foregroundStyle(isThis ? Surface.window : Surface.musicAccent)
        }
        .buttonStyle(.plain)
        .help(isThis ? "Arrêter l'extrait" : "Écouter un extrait de 30 s (sans toucher à Music)")
        .accessibilityLabel(isThis ? "Arrêter l'extrait" : "Écouter l'extrait de 30 s de \(title)")
    }

    @ViewBuilder
    private var previewZone: some View {
        if let current = previewing {
            HStack(spacing: 10) {
                Button {
                    preview.stop()
                    previewing = nil
                } label: {
                    Icon.stopFill.view(size: 12)
                        .frame(width: 32, height: 32)
                        .background(Surface.musicAccent, in: .circle)
                        .foregroundStyle(Surface.window)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Arrêter l'extrait")
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(current.title) · extrait 30 s").font(.system(size: 12)).lineLimit(1)
                    Capsule().fill(Color.white.opacity(0.1)).frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule().fill(Surface.musicAccent)
                                    .frame(width: proxy.size.width * (current.file == nil ? 0 : preview.progress))
                            }
                        }
                        .frame(height: 4)
                }
                if current.file == nil { ProgressView().controlSize(.small) }
            }
            .padding(10)
            .background(Surface.well, in: .rect(cornerRadius: 12))
            .task(id: current.key) {
                // Avancement de l'extrait, relu 5 fois par seconde tant qu'il joue.
                while !Task.isCancelled {
                    preview.refreshProgress()
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            .onChange(of: preview.playingItem) { if preview.playingItem == nil, previewing?.file != nil { previewing = nil } }
        }
    }
}
