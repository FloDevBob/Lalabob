import ControllerDrivers
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
    static let controllerDefaultsKey = "lastControllerModel"

    public private(set) var show: Show
    public var selectedGridIndex: Int
    public var selection: GridPosition?
    public var mode: InteractionMode = .live

    /// État de lecture des pads qui jouent ou sont en pause (les autres sont absents).
    public private(set) var playback: [Pad.ID: PlaybackEvent] = [:]
    public private(set) var outputDevices: [AudioOutputDevice] = []
    /// `nil` = sortie par défaut du système.
    public private(set) var selectedOutputUID: String?
    /// Dernier import de son raté, à montrer à l'utilisateur (`nil` si rien à signaler).
    public internal(set) var importError: String?
    /// Le contrôleur physique actuellement relié (Launchpad, APC), s'il y en a un.
    public private(set) var connectedController: ControllerModel?
    /// Dernier contrôleur relié (mémorisé) : donne les notes à envoyer à LightKey quand aucun n'est branché.
    public private(set) var lastControllerModel: ControllerModel?
    /// Nom du contrôleur relié, pour l'affichage.
    public var connectedControllerName: String? { connectedController?.displayName }

    /// Gestionnaire d'annulation de la fenêtre (⌘Z). Fourni par la vue.
    @ObservationIgnored public weak var undoManager: UndoManager?
    /// Pad copié (⌘C / ⌘X), collé avec un nouvel identifiant.
    var clipboard: Pad?

    /// Dossier de travail des sons du spectacle (le futur `Audio/` du paquet).
    @ObservationIgnored public private(set) var audioDirectory: URL?
    @ObservationIgnored private let audio: any AudioEngineControlling
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let commands: AsyncStream<AudioCommand>.Continuation
    @ObservationIgnored private let log = Logger(subsystem: "fr.lalabob.app", category: "engine")
    /// Clics à l'écran sur un pad lumière : `ControllerSession` les transmet à LightKey quand cette fenêtre est active.
    @ObservationIgnored var lightPressHandler: (@MainActor (GridPosition) -> Void)?
    /// Appelé après chaque changement du spectacle (le document en garde une copie pour l'enregistrer).
    @ObservationIgnored public var onShowChange: (@MainActor (Show) -> Void)?

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
        self.lastControllerModel = defaults.string(forKey: Self.controllerDefaultsKey).flatMap(ControllerModel.init(rawValue:))

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
            guard let pad = currentGrid[position] else { return }
            switch pad.content {
            case .audio: commands.yield(.trigger(pad.id))
            case .light: lightPressHandler?(position)
            }
        }
    }

    /// Appui sur un pad du contrôleur : joue toujours, quel que soit le mode de l'écran.
    func pressFromController(at position: GridPosition) {
        guard let pad = pad(at: position), case .audio = pad.content else { return }
        commands.yield(.trigger(pad.id))
    }

    func setConnectedController(_ model: ControllerModel?) {
        connectedController = model
        if let model {
            lastControllerModel = model
            defaults.set(model.rawValue, forKey: Self.controllerDefaultsKey)
        }
    }

    /// Ce que les LED du contrôleur doivent montrer : le reflet de la grille affichée.
    var ledStates: [GridPosition: LEDState] {
        LEDPlanner.states(for: currentGrid, playback: playback)
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
        onShowChange?(show)
        if show.grids[selectedGridIndex].columns[column].kind == .audio {
            commands.yield(.level(column: column, level: level))
        }
    }

    /// Remplace le spectacle ouvert (relecture d'un document).
    public func replaceShow(_ newShow: Show) {
        show = newShow
        onShowChange?(show)
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

    // MARK: - Modification et annulation

    /// Applique une modification au spectacle. `change` reçoit une copie et l'index de l'onglet affiché ;
    /// il renvoie `false` pour ne rien faire. Une modification sans effet n'enregistre pas d'annulation.
    @discardableResult
    func commit(_ actionName: String, _ change: (inout Show, Int) -> Bool) -> Bool {
        var updated = show
        guard change(&updated, selectedGridIndex), updated != show else { return false }
        apply(updated, actionName: actionName)
        return true
    }

    private func apply(_ newShow: Show, actionName: String) {
        let previous = show
        show = newShow
        if !show.grids.indices.contains(selectedGridIndex) { selectedGridIndex = show.grids.count - 1 }
        syncAudio()
        onShowChange?(show)

        guard let undoManager else { return }
        let isReplaying = undoManager.isUndoing || undoManager.isRedoing
        if !isReplaying { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated { controller.apply(previous, actionName: actionName) }
        }
        undoManager.setActionName(actionName)
        if !isReplaying { undoManager.endUndoGrouping() }
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

    deinit {
        commands.finish()  // libère le moteur audio de cette fenêtre
    }
}
