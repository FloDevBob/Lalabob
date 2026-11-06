import Foundation
import LalabobImport
import LalabobModel

// L'app ne dépend que de LalabobEngine : elle y trouve les types d'import dont l'interface a besoin.
public typealias AbletonImportError = LalabobImport.AbletonImportError
public typealias AbletonImportReport = LalabobImport.AbletonImportReport
public typealias LiveSetOverflow = LalabobImport.LiveSetOverflow

/// Un Live Set lu, prêt à être importé dans un spectacle.
public struct LiveSetImportRequest: Sendable {
    let liveSet: AbletonLiveSet
    /// Le `.als` lui-même.
    let liveSetURL: URL
    /// Ce que l'utilisateur a choisi (le `.als` ou le dossier du projet) : l'accès bac à sable à rouvrir pour chercher les sons.
    let pickedURL: URL

    /// Nom du Live Set, sans extension.
    public var name: String { liveSetURL.deletingPathExtension().lastPathComponent }
    public var audioTrackCount: Int { liveSet.audioTracks.count }
    public var sceneCount: Int { liveSet.usedSceneCount }
    public var clipCount: Int { liveSet.clipCount }
    /// Dossier choisi par l'utilisateur, s'il a choisi un dossier : on y cherche aussi les sons par leur nom.
    var searchRoots: [URL] {
        (try? pickedURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true ? [pickedURL] : []
    }
    /// Plus de 6 pistes audio ou plus de 8 scènes : l'utilisateur doit choisir entre découper et tronquer.
    public var needsLayoutChoice: Bool { liveSet.exceedsSingleGrid }
}

/// Lecture d'un Live Set Ableton et recherche de ses sons sur le disque (les entrées-sorties de l'import).
public enum AbletonImporter {
    /// Le `.als` désigné par `url` : le fichier lui-même, ou l'unique `.als` d'un dossier — à sa racine (dossier de projet Live) ou,
    /// à défaut, dans ses sous-dossiers directs (dossier qui contient le projet et les sons ; `Backup` est ignoré).
    public static func locateLiveSet(at url: URL) throws(AbletonImportError) -> URL {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        guard isFolder else {
            guard url.pathExtension.lowercased() == "als" else { throw .notALiveSet }
            return url
        }
        let manager = FileManager.default
        func entries(of folder: URL) -> [URL] {
            // On rebâtit les URL depuis le dossier reçu : `contentsOfDirectory(at:)` rend des chemins résolus (/var → /private/var).
            ((try? manager.contentsOfDirectory(atPath: folder.path)) ?? [])
                .filter { !$0.hasPrefix(".") }
                .map { folder.appending(path: $0) }
        }
        func sets(in folder: URL) -> [URL] { entries(of: folder).filter { $0.pathExtension.lowercased() == "als" } }
        var found = sets(in: url)
        if found.isEmpty {
            for sub in entries(of: url)
            where sub.lastPathComponent != "Backup"
                && (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            {
                found += sets(in: sub)
            }
        }
        found.sort { $0.path < $1.path }
        guard let first = found.first else { throw .noLiveSetInFolder }
        guard found.count == 1 else {
            throw .severalLiveSetsInFolder(found.map { $0.path.replacingOccurrences(of: url.path + "/", with: "") })
        }
        return first
    }

    /// Lit le Live Set. `url` vient d'un sélecteur de fichiers (accès bac à sable à ouvrir le temps de la lecture).
    public static func read(at url: URL) throws(AbletonImportError) -> LiveSetImportRequest {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let liveSetURL = try locateLiveSet(at: url)
        guard let data = try? Data(contentsOf: liveSetURL, options: .mappedIfSafe) else { throw .cannotRead }
        let liveSet = try AbletonLiveSetReader.read(fileData: data)
        return LiveSetImportRequest(liveSet: liveSet, liveSetURL: liveSetURL, pickedURL: url)
    }

    /// Où est le son d'un clip ? D'abord au chemin relatif au dossier du `.als`, puis au chemin absolu mémorisé par Live, puis
    /// par son nom n'importe où sous l'un des dossiers de recherche (dossier du projet, dossier choisi par l'utilisateur).
    ///
    /// Le chemin relatif remonte souvent hors du projet (`../../Musique/Sons/x.mp3`) : les `..` sont donc acceptés. Le garde-fou n'est
    /// pas le chemin mais le bac à sable de l'app (seuls les dossiers choisis par l'utilisateur sont lisibles) et le filtre des formats
    /// audio de `AudioImporter`.
    public static func sampleURL(for reference: AbletonSampleReference, liveSetFolder: URL, searchRoots: [URL] = []) -> URL? {
        var candidates: [URL] = []
        let relative = reference.relativePath
        if !relative.isEmpty, !relative.hasPrefix("/") {
            candidates.append(liveSetFolder.appending(path: relative).standardizedFileURL)
        }
        if reference.absolutePath.hasPrefix("/") { candidates.append(URL(fileURLWithPath: reference.absolutePath)) }
        for candidate in candidates where isRegularFile(candidate) { return candidate }
        for root in [liveSetFolder] + searchRoots {
            if let found = findFile(named: reference.fileName, under: root) { return found }
        }
        return nil
    }

    /// Recherche bornée (un projet Live compte rarement plus de quelques milliers de fichiers).
    static func findFile(named name: String, under folder: URL, limit: Int = 20_000) -> URL? {
        guard !name.isEmpty,
            let walker = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return nil }
        var visited = 0
        for case let url as URL in walker {
            visited += 1
            if visited > limit { return nil }
            if url.lastPathComponent == name, isRegularFile(url) { return url }
        }
        return nil
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }
}

extension ShowController {
    /// Ajoute au spectacle les grilles d'un Live Set (annulable d'un seul ⌘Z) : une piste audio par colonne son, une scène
    /// par ligne. Les sons trouvés sont copiés dans le spectacle ; ceux qui manquent donnent des pads muets, signalés
    /// dans le compte rendu. Renvoie `nil` si rien n'a été importé (spectacle verrouillé, rien à importer, limite de grilles).
    @discardableResult
    public func importLiveSet(_ request: LiveSetImportRequest, overflow: LiveSetOverflow) -> AbletonImportReport? {
        guard !refuseWhileLocked() else { return nil }
        guard let audioDirectory else {
            importError = "Ce spectacle n'a pas de dossier de sons : import impossible."
            return nil
        }
        let room = Show.maximumGridCount - show.grids.count
        guard room > 0 else {
            importError = "Le spectacle a déjà \(Show.maximumGridCount) grilles, le maximum."
            return nil
        }

        let scoped = request.pickedURL.startAccessingSecurityScopedResource()
        defer { if scoped { request.pickedURL.stopAccessingSecurityScopedResource() } }
        let folder = request.liveSetURL.deletingLastPathComponent()
        var copied: [String: String] = [:]
        var notFound: Set<String> = []

        let plan = AbletonShowBuilder.build(request.liveSet, baseName: request.name, overflow: overflow, maximumGrids: room) { reference in
            let key = reference.relativePath + "\n" + reference.absolutePath
            if let name = copied[key] { return name }
            if notFound.contains(key) { return nil }
            guard let url = AbletonImporter.sampleURL(for: reference, liveSetFolder: folder, searchRoots: request.searchRoots),
                let name = try? AudioImporter.importFile(at: url, into: audioDirectory)
            else {
                notFound.insert(key)
                return nil
            }
            copied[key] = name
            return name
        }
        guard !plan.grids.isEmpty else {
            importError = "Ce Live Set ne contient aucun clip audio dans la vue Session : rien à importer."
            return nil
        }

        let added = commit("Importer un Live Set") { show, _ in
            show.grids.append(contentsOf: plan.grids)
            return true
        }
        guard added else { return nil }
        selectGrid(at: show.grids.count - plan.grids.count)
        return plan.report
    }
}
