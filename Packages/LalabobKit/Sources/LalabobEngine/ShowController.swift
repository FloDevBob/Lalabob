import Foundation
import LalabobAudio
import LalabobModel
import Observation
import os

/// Ce qu'un clic sur un pad provoque.
public enum InteractionMode: String, Sendable {
    /// Un clic sélectionne le pad.
    case edit
    /// Un clic agit comme un appui sur le contrôleur.
    case live
}

/// Détient le spectacle ouvert : la seule source de vérité de l'app.
///
/// L'écran et les LED du contrôleur en sont deux reflets. Toute modification passe par
/// une méthode de ce type, pour pouvoir l'annuler (⌘Z) et la répercuter sur le matériel.
///
/// Les commandes audio partent dans une file unique : elles arrivent au moteur dans l'ordre
/// où l'interface les a données.
@MainActor
@Observable
public final class ShowController {
    public static let outputDefaultsKey = "audioOutputUID"

    public private(set) var show: Show
    public var selectedGridIndex: Int
    public var selection: GridPosition?
    public var mode: InteractionMode = .live

    /// État de lecture des pads qui jouent ou sont en pause (les autres sont absents).
    public private(set) var playback: [Pad.ID: PlaybackEvent] = [:]
    public private(set) var outputDevices: [AudioOutputDevice] = []
    /// `nil` = sortie par défaut du système.
    public private(set) var selectedOutputUID: String?

    @ObservationIgnored private let audioDirectory: URL?
    @ObservationIgnored private let audio: any AudioEngineControlling
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let commands: AsyncStream<AudioCommand>.Continuation
    @ObservationIgnored private let log = Logger(subsystem: "fr.lalabob.app", category: "engine")

    private enum AudioCommand: Sendable {
        case configure(Show)
        case trigger(Pad.ID)
        case togglePause(Pad.ID)
        case stop(Pad.ID)
        case stopAll
        case level(column: Int, level: Double)
        case output(String?)
    }

    public init(
        show: Show = .new(),
        audio: any AudioEngineControlling = SilentAudioEngine(),
        audioDirectory: URL? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.show = show
        self.selectedGridIndex = 0
        self.audio = audio
        self.audioDirectory = audioDirectory
        self.defaults = defaults
        self.selectedOutputUID = defaults.string(forKey: Self.outputDefaultsKey)

        let (stream, continuation) = AsyncStream.makeStream(of: AudioCommand.self, bufferingPolicy: .unbounded)
        self.commands = continuation
        let log = self.log
        Task.detached {
            for await command in stream {
                do {
                    switch command {
                    case .configure(let show):
                        if let directory = audioDirectory { try await audio.configure(show: show, audioDirectory: directory) }
                    case .trigger(let id): await audio.trigger(id)
                    case .togglePause(let id): await audio.togglePause(id)
                    case .stop(let id): await audio.stop(id)
                    case .stopAll: await audio.stopAll()
                    case .level(let column, let level): await audio.setColumnLevel(column, level: level)
                    case .output(let uid): try await audio.setOutputDevice(uid: uid)
                    }
                } catch {
                    log.error("Commande audio échouée : \(error.localizedDescription)")
                }
            }
        }

        if let uid = selectedOutputUID { continuation.yield(.output(uid)) }
        syncAudio()
    }

    public var currentGrid: PadGrid { show.grids[selectedGridIndex] }

    public func selectGrid(at index: Int) {
        guard show.grids.indices.contains(index) else { return }
        selectedGridIndex = index
        syncColumnLevels()
    }

    public func pad(at position: GridPosition) -> Pad? {
        guard position.isValid else { return nil }
        return currentGrid[position]
    }

    // MARK: - Commandes

    /// Clic sur une case : appui en mode Live, sélection en mode Édition.
    public func press(at position: GridPosition) {
        guard position.isValid else { return }
        switch mode {
        case .edit:
            selection = position
        case .live:
            guard let pad = currentGrid[position], case .audio = pad.content else { return }
            commands.yield(.trigger(pad.id))
        }
    }

    public func togglePause(at position: GridPosition) {
        guard let pad = pad(at: position), case .audio = pad.content else { return }
        commands.yield(.togglePause(pad.id))
    }

    public func stop(at position: GridPosition) {
        guard let pad = pad(at: position), case .audio = pad.content else { return }
        commands.yield(.stop(pad.id))
    }

    /// « Tout arrêter » (Échap).
    public func stopAll() {
        commands.yield(.stopAll)
    }

    /// Fader d'une colonne de la grille affichée. Niveau borné à 0…1.
    public func setColumnLevel(_ column: Int, level: Double) {
        guard (0..<PadGrid.size).contains(column) else { return }
        let level = Gain.faderLevel(level)
        show.grids[selectedGridIndex].columns[column].level = level
        if show.grids[selectedGridIndex].columns[column].kind == .audio {
            commands.yield(.level(column: column, level: level))
        }
    }

    /// Remplace le spectacle ouvert (ouverture d'un document, sons d'essai).
    public func replaceShow(_ newShow: Show) {
        show = newShow
        selectedGridIndex = 0
        selection = nil
        playback = [:]
        syncAudio()
    }

    // MARK: - Sortie audio

    public func selectOutput(uid: String?) {
        selectedOutputUID = uid
        defaults.set(uid, forKey: Self.outputDefaultsKey)
        commands.yield(.output(uid))
    }

    public func refreshOutputDevices() {
        outputDevices = AudioOutputDevices.available()
    }

    /// À lancer une fois (`.task`) : suit les branchements de cartes son.
    public func observeOutputDevices() async {
        refreshOutputDevices()
        for await _ in AudioOutputDevices.changes() { refreshOutputDevices() }
    }

    // MARK: - État de lecture

    /// À lancer une fois (`.task`) : répercute l'état de lecture du moteur sur l'écran.
    public func observePlayback() async {
        for await event in audio.events {
            if event.state == .idle {
                playback[event.pad] = nil
            } else {
                playback[event.pad] = event
            }
        }
    }

    // MARK: - Synchronisation

    private func syncAudio() {
        commands.yield(.configure(show))
        syncColumnLevels()
    }

    private func syncColumnLevels() {
        for (index, column) in currentGrid.columns.enumerated() where column.kind == .audio {
            commands.yield(.level(column: index, level: column.level))
        }
    }

    // MARK: - Sons d'essai (avant le jalon 4 : pas encore de glisser-déposer)

    private nonisolated static let audioExtensions: Set<String> = ["wav", "wave", "aif", "aiff", "caf", "mp3", "m4a", "aac", "flac"]

    /// Un spectacle d'une grille dont les colonnes sons sont remplies par les fichiers donnés
    /// (triés par nom, colonne après colonne). Les fichiers qui ne sont pas des sons sont ignorés.
    public nonisolated static func trialShow(fileNames: [String]) -> Show {
        let sounds =
            fileNames
            .filter { AudioClip.isSafeFileName($0) && audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let tints = Tint.allCases.filter { $0 != .blanc && $0 != .graphite }
        var grid = PadGrid.empty(name: "Sons d'essai")
        let soundColumns = (0..<PadGrid.size).filter { !PadGrid.defaultLightColumns.contains($0) }
        for (index, name) in sounds.prefix(soundColumns.count * PadGrid.size).enumerated() {
            let column = soundColumns[index / PadGrid.size]
            grid.columns[column].slots[index % PadGrid.size] = Pad(
                title: (name as NSString).deletingPathExtension,
                tint: tints[index % tints.count],
                content: .audio(clip: AudioClip(fileName: name))
            )
        }
        return Show(name: "Sons d'essai", grids: [grid])
    }

    /// Remplit la grille avec les sons du dossier `Audio/`.
    public func loadTrialSounds() {
        guard let audioDirectory,
            let names = try? FileManager.default.contentsOfDirectory(atPath: audioDirectory.path)
        else { return }
        replaceShow(Self.trialShow(fileNames: names))
    }
}
