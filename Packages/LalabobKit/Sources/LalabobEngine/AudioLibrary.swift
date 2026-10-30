import Foundation
import LalabobAudio
import Observation
import os

/// Un son de la bibliothèque (colonne de gauche).
public struct AudioLibraryItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    /// `nil` si le fichier n'a pas pu être lu.
    public let duration: TimeInterval?
    public var id: URL { url }

    public init(url: URL, name: String, duration: TimeInterval?) {
        self.url = url
        self.name = name
        self.duration = duration
    }
}

public enum AudioLibrary {
    /// Sons d'un dossier (sans les sous-dossiers), triés comme dans le Finder, avec leur durée.
    public static func items(in folder: URL) async -> [AudioLibraryItem] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        return
            urls
            .filter { AudioImporter.isSupported($0) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { AudioLibraryItem(url: $0, name: $0.lastPathComponent, duration: AudioFileInfo.duration(of: $0)) }
    }

    /// Recherche sans tenir compte des majuscules ni des accents.
    public static func filter(_ items: [AudioLibraryItem], query: String) -> [AudioLibraryItem] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return items }
        return items.filter { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// « 0:04 », « 1:02 », « 1:02:05 ».
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let (hours, minutes, secs) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// Dossiers favoris de la bibliothèque, mémorisés par signets (sandbox) pour y revenir au prochain lancement.
@MainActor
@Observable
public final class LibraryController {
    public struct Favorite: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let url: URL
        public var name: String { url.lastPathComponent }
    }

    public private(set) var favorites: [Favorite] = []
    public private(set) var currentFavorite: Favorite.ID?
    public private(set) var items: [AudioLibraryItem] = []
    /// Son sélectionné dans la liste (surbrillance ; servira à la pré-écoute).
    public private(set) var selectedItem: AudioLibraryItem.ID?
    public var query = ""

    public var visibleItems: [AudioLibraryItem] { AudioLibrary.filter(items, query: query) }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let securityScoped: Bool
    @ObservationIgnored private var bookmarks: [UUID: Data] = [:]
    @ObservationIgnored private var accessed: Set<URL> = []
    @ObservationIgnored private let log = Logger(subsystem: "fr.lalabob.app", category: "library")
    private static let defaultsKey = "libraryFavorites"

    /// `securityScoped: false` pour les tests (hors sandbox).
    public init(defaults: UserDefaults = .standard, securityScoped: Bool = true) {
        self.defaults = defaults
        self.securityScoped = securityScoped
        restore()
    }

    /// Ajoute un dossier choisi par l'utilisateur et l'affiche.
    public func addFavorite(_ url: URL) async {
        let standardized = url.standardizedFileURL
        if let existing = favorites.first(where: { $0.url.standardizedFileURL == standardized }) {
            await select(existing.id)
            return
        }
        let scoped = securityScoped && url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        else {
            log.error("Signet impossible pour \(url.path)")
            return
        }
        let favorite = Favorite(id: UUID(), url: url)
        bookmarks[favorite.id] = data
        favorites.append(favorite)
        save()
        await select(favorite.id)
    }

    public func removeFavorite(_ id: Favorite.ID) {
        if let favorite = favorites.first(where: { $0.id == id }), accessed.remove(favorite.url) != nil {
            favorite.url.stopAccessingSecurityScopedResource()
        }
        favorites.removeAll { $0.id == id }
        bookmarks[id] = nil
        if currentFavorite == id {
            currentFavorite = nil
            items = []
            selectedItem = nil
        }
        save()
    }

    /// Affiche les sons d'un dossier favori. L'accès au dossier reste ouvert pour pouvoir glisser ses sons.
    public func select(_ id: Favorite.ID) async {
        guard let favorite = favorites.first(where: { $0.id == id }) else { return }
        if securityScoped, !accessed.contains(favorite.url), favorite.url.startAccessingSecurityScopedResource() {
            accessed.insert(favorite.url)
        }
        if currentFavorite != id { selectedItem = nil }
        currentFavorite = id
        items = await AudioLibrary.items(in: favorite.url)
    }

    public func selectItem(_ id: AudioLibraryItem.ID?) {
        selectedItem = id
    }

    public func refresh() async {
        if let currentFavorite { await select(currentFavorite) }
    }

    // MARK: - Signets

    private var bookmarkCreationOptions: URL.BookmarkCreationOptions { securityScoped ? [.withSecurityScope] : [] }
    private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions { securityScoped ? [.withSecurityScope] : [] }

    private func restore() {
        let stored = defaults.array(forKey: Self.defaultsKey) as? [Data] ?? []
        for data in stored {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: bookmarkResolutionOptions, bookmarkDataIsStale: &stale),
                FileManager.default.fileExists(atPath: url.path)
            else { continue }  // dossier disparu : on l'oublie
            let id = UUID()
            let fresh = stale ? (try? url.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)) : nil
            bookmarks[id] = fresh ?? data
            favorites.append(Favorite(id: id, url: url))
        }
        save()
    }

    private func save() {
        defaults.set(favorites.compactMap { bookmarks[$0.id] }, forKey: Self.defaultsKey)
    }
}
