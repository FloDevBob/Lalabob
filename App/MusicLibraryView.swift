import LalabobDesign
import LalabobEngine
import LalabobModel
import SwiftUI

/// Panneau de gauche d'une grille Apple Music (déverrouillé) : état de Music, recherche, playlists en arbre, morceaux de la
/// playlist choisie (sélection multiple, glisser vers les pads), morceaux restés dans le nuage.
struct MusicLibraryView: View {
    @Environment(MusicLibraryController.self) private var library
    @Environment(ShowController.self) private var controller
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow
            if library.status == .running {
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
}
