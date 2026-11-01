import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobMIDI
import LalabobModel
import Observation
import os

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
    /// Cases sélectionnées (Maj = plage rectangulaire, ⌘ = ajout / retrait). Vide si rien n'est sélectionné.
    public internal(set) var selectedPositions: Set<GridPosition> = []
    /// Case « principale » : celle que montre l'inspecteur quand elle est seule, et l'ancre des plages (Maj).
    var primarySelection: GridPosition?
    /// Extrémité mobile de la sélection au clavier (Maj + flèches) ; l'autre extrémité est la case principale.
    var selectionCursor: GridPosition?
    /// Mode « Appairage lumière » : les cases lumière attendent qu'une cue de LightKey leur soit rattachée. Jamais enregistré.
    public internal(set) var isPairingLights = false
    /// Case lumière qui vient d'être appairée et dont le nom attend d'être saisi.
    public internal(set) var pairingNaming: GridPosition?
    /// Appairage lumière : la colonne dont le fader est la cible (au lieu d'un pad).
    public internal(set) var pairingFader: Int?
    /// Affecter une case remplace toute la sélection par cette seule case (`nil` : tout désélectionner).
    public var selection: GridPosition? {
        get { primarySelection }
        set {
            primarySelection = newValue
            selectedPositions = newValue.map { [$0] } ?? []
            if newValue != nil { pairingFader = nil }  // la cible de l'appairage est un pad ou un fader, jamais les deux
        }
    }
    /// Cadenas : verrouillé, le spectacle se joue (clic, contrôleur, faders, onglets) mais ne se modifie pas.
    /// Verrouiller efface la sélection (l'inspecteur se ferme).
    public var isLocked: Bool {
        didSet {
            if isLocked {
                selection = nil
                isPairingLights = false  // aucun appairage en scène
                pairingNaming = nil
                pairingFader = nil
            }
            if !isLocked { lockNotice = nil }
        }
    }
    /// Message à afficher quand on tente de modifier un spectacle verrouillé (`nil` sinon).
    public private(set) var lockNotice: String?

    /// Crêtes du signal de chaque colonne (vumètres). Lues par l'interface à chaque image, sans passer par le moteur.
    public var meters: ColumnMeters { audio.meters }

    /// État de lecture des pads qui jouent ou sont en pause (les autres sont absents).
    public private(set) var playback: [Pad.ID: PlaybackEvent] = [:]
    /// État de chaque cue lumière d'après le retour de LightKey, par case (la même sur toutes les grilles : c'est la note du contrôleur).
    public private(set) var lightStates: [GridPosition: LightState] = [:]
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
    /// Pad d'où part le glisser en cours (`nil` hors glisser) : donne le décalage d'un glisser de groupe.
    public internal(set) var draggedPosition: GridPosition?
    /// Cases où tomberait le groupe pendant un glisser de plusieurs pads (`nil` : pas de glisser de groupe).
    public internal(set) var dragPreview: DropPreview?

    /// Aperçu d'un glisser de groupe : les cases visées et si le dépôt serait accepté.
    public struct DropPreview: Equatable, Sendable {
        public let positions: Set<GridPosition>
        public let isAllowed: Bool
        public let isCopy: Bool
    }

    /// Pads copiés (⌘C / ⌘X) avec leur position relative, collés avec de nouveaux identifiants.
    var clipboard: [ClipboardEntry]?

    /// Un pad du presse-papiers et son décalage par rapport au coin haut-gauche du groupe copié.
    struct ClipboardEntry {
        let pad: Pad
        let columnOffset: Int
        let rowOffset: Int
    }

    /// Dossier de travail des sons du spectacle (le futur `Audio/` du paquet).
    @ObservationIgnored public private(set) var audioDirectory: URL?
    @ObservationIgnored private let audio: any AudioEngineControlling
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let commands: AsyncStream<AudioCommand>.Continuation
    @ObservationIgnored private let log = Logger(subsystem: "fr.lalabob.app", category: "engine")
    /// Clics à l'écran sur un pad lumière : `ControllerSession` les transmet à LightKey quand cette fenêtre est active.
    @ObservationIgnored var lightPressHandler: (@MainActor (GridPosition) -> Void)?
    /// Fader d'une colonne lumière déplacé à l'écran : `ControllerSession` le répète vers LightKey quand cette fenêtre est active.
    /// Faders physiques décrochés : colonne → position réelle du fader (0…1). Ils n'agissent pas encore sur leur colonne
    /// (prise en main progressive, `FaderPickup`) ; l'interface en fait un repère sur la carte de la colonne.
    public private(set) var waitingFaders: [Int: Double] = [:]
    @ObservationIgnored private var faderPickup = FaderPickup()
    @ObservationIgnored var lightFaderHandler: (@MainActor (_ column: Int, _ level: Double) -> Void)?
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
        case padGain(Pad.ID, Double)
        case seek(Pad.ID, TimeInterval)
    }

    public init(
        show: Show = .new(),
        audio: any AudioEngineControlling = SilentAudioEngine(),
        audioDirectory: URL? = nil,
        defaults: UserDefaults = .standard,
        isLocked: Bool = false
    ) {
        self.show = show
        self.isLocked = isLocked
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
                    case .padGain(let id, let db): await audio.setPadGain(id, gainDB: db)
                    case .seek(let id, let elapsed): await audio.seek(id, to: elapsed)
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
        syncHardwareFaders()
    }

    public func pad(at position: GridPosition) -> Pad? {
        guard position.isValid else { return nil }
        return currentGrid[position]
    }

    // MARK: - Commandes

    /// Clic simple sur une case : la sélectionne, **sans jouer** (déverrouillé comme verrouillé : un son ne part qu'au
    /// double-clic, `audition`, ou sur le contrôleur). Déverrouillé, ⇧ étend la sélection en rectangle et ⌘ ajoute ou retire
    /// une case ; verrouillé, il n'y a que la case cliquée (rien à éditer en groupe) et le panneau de jeu s'ouvre pour un son.
    public func press(at position: GridPosition, mode: SelectionMode = .replace) {
        guard position.isValid else { return }
        switch isLocked ? .replace : mode {
        case .replace:
            selection = position
        case .range:
            selectRange(to: position)
        case .toggle:
            toggleSelection(at: position)
        }
    }

    /// Flèches du clavier : déplace la sélection d'une case (sans sortir de la grille). Avec `extend` (Maj), la sélection
    /// devient le rectangle entre la case principale et la nouvelle case, comme un Maj-clic ; verrouillé, il n'y a toujours
    /// qu'une case. Sans sélection, la première flèche sélectionne la case en haut à gauche.
    public func moveSelection(dx: Int, dy: Int, extend: Bool = false) {
        guard let start = selectionCursor.flatMap({ selectedPositions.contains($0) ? $0 : nil }) ?? primarySelection else {
            let first = GridPosition(column: 0, row: 0)
            selection = first
            selectionCursor = first
            return
        }
        let last = PadGrid.size - 1
        let target = GridPosition(column: min(max(start.column + dx, 0), last), row: min(max(start.row + dy, 0), last))
        if extend, !isLocked {
            selectRange(to: target)
        } else {
            selection = target
        }
        selectionCursor = target
    }

    /// Comment un clic modifie la sélection (déverrouillé).
    public enum SelectionMode: Sendable {
        /// Clic simple : cette case seule.
        case replace
        /// Maj-clic : toutes les cases du rectangle entre l'ancre et la case cliquée.
        case range
        /// ⌘-clic : ajoute ou retire cette case.
        case toggle
    }

    /// Sélectionne ces cases (la première devient la case principale) ; la liste vide désélectionne tout.
    func selectPositions(_ positions: [GridPosition]) {
        primarySelection = positions.first
        selectedPositions = Set(positions)
    }

    private func selectRange(to position: GridPosition) {
        guard let anchor = primarySelection else {
            selection = position
            return
        }
        let columns = min(anchor.column, position.column)...max(anchor.column, position.column)
        let rows = min(anchor.row, position.row)...max(anchor.row, position.row)
        selectedPositions = Set(columns.flatMap { column in rows.map { GridPosition(column: column, row: $0) } })
    }

    private func toggleSelection(at position: GridPosition) {
        guard primarySelection != nil else {
            selection = position
            return
        }
        if selectedPositions.contains(position) {
            selectedPositions.remove(position)
            if primarySelection == position {
                // Le pad principal passe à une case restante (la plus haute à gauche, pour rester prévisible).
                primarySelection = selectedPositions.min { ($0.column, $0.row) < ($1.column, $1.row) }
            }
        } else {
            selectedPositions.insert(position)
        }
    }

    /// Double-clic : joue le pad (son ou cue lumière), déverrouillé comme verrouillé. Jouer n'est pas modifier.
    public func audition(at position: GridPosition) {
        guard position.isValid else { return }
        play(at: position)
    }

    /// Lecture d'un pad depuis le panneau du bas : marche aussi verrouillé (c'est du jeu, pas de l'édition).
    public func playPad(at position: GridPosition) {
        guard position.isValid else { return }
        play(at: position)
    }

    private func play(at position: GridPosition) {
        guard let pad = currentGrid[position] else { return }
        switch pad.content {
        case .audio:
            commands.yield(.trigger(pad.id))
            if isLocked { selection = position }
        case .light: lightPressHandler?(position)
        }
    }

    /// Volume d'un pad pendant qu'on déplace la jauge : le moteur le suit tout de suite, y compris sur un son
    /// qui joue. Rien n'est écrit dans le spectacle ni dans l'historique : `setGain` valide la valeur finale
    /// (une seule annulation). Marche aussi verrouillé ; ignoré si la case n'a pas de son.
    public func previewGain(at position: GridPosition, _ decibels: Double) {
        guard let pad = pad(at: position), case .audio = pad.content else { return }
        let clamped = AudioClip(fileName: "x").withGain(decibels).gainDB
        commands.yield(.padGain(pad.id, clamped))
    }

    /// Déplace la tête de lecture d'un pad (clic ou glisser sur la forme d'onde). `fileTime` : point cliqué, en secondes
    /// dans le fichier ; il est ramené à la partie élaguée. Le son joue de là, ou reste en pause là, ou démarre de là
    /// s'il était arrêté. Marche aussi verrouillé (le spectacle n'est pas modifié) ; ignoré si la case n'a pas de son.
    public func seek(at position: GridPosition, toFileTime fileTime: TimeInterval, fileDuration: TimeInterval) {
        guard let pad = pad(at: position), case .audio(let clip) = pad.content else { return }
        commands.yield(.seek(pad.id, clip.playbackOffset(atFileTime: fileTime, fileDuration: fileDuration)))
    }

    /// `true` (et message à l'écran) si le spectacle est verrouillé : l'appelant ne doit rien modifier.
    func refuseWhileLocked() -> Bool {
        guard isLocked else { return false }
        lockNotice = "Spectacle verrouillé : ouvrez le cadenas (⌘L) pour le modifier."
        return true
    }

    /// L'interface signale un geste d'édition tenté sur un spectacle verrouillé (glisser, renommer…).
    public func notifyLocked() {
        _ = refuseWhileLocked()
    }

    public func dismissLockNotice() {
        lockNotice = nil
    }

    /// Appui sur un pad du contrôleur : joue toujours, quel que soit le mode de l'écran.
    func pressFromController(at position: GridPosition) {
        guard let pad = pad(at: position), case .audio = pad.content else { return }
        commands.yield(.trigger(pad.id))
        if isLocked { selection = position }
    }

    /// État d'une case lumière d'après LightKey (`.unknown` tant qu'il n'a rien dit).
    public func lightState(at position: GridPosition) -> LightState { lightStates[position] ?? .unknown }

    func setLightStates(_ states: [GridPosition: LightState]) {
        guard states != lightStates else { return }
        lightStates = states
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
        LEDPlanner.states(for: currentGrid, playback: playback, lightStates: lightStates)
    }

    public func togglePause(at position: GridPosition) {
        guard let pad = pad(at: position), case .audio = pad.content else { return }
        commands.yield(.togglePause(pad.id))
    }

    /// Espace : sur le pad sélectionné, pause si le son joue, reprise s'il est en pause, lecture s'il est arrêté
    /// (ou cue lumière envoyée). Marche aussi verrouillé : c'est du jeu, pas de l'édition.
    public func togglePlaybackOfSelection() {
        guard let position = selection, let pad = pad(at: position) else { return }
        if case .audio = pad.content, playback[pad.id]?.state.isActive == true {
            commands.yield(.togglePause(pad.id))
        } else {
            play(at: position)
        }
    }

    /// Bouton lecture / stop d'un pad son : arrête un son qui joue, reprend un son en pause, lance un son à l'arrêt.
    /// Marche aussi verrouillé (c'est du jeu). Sans effet sur une case vide ou une cue lumière.
    public func togglePlayStop(at position: GridPosition) {
        guard let pad = pad(at: position), case .audio = pad.content else { return }
        switch playback[pad.id]?.state {
        case .playing: stop(at: position)
        case .paused: togglePause(at: position)
        default: play(at: position)
        }
    }

    /// Retour : lecture / relance du pad sélectionné (son : selon son réglage « Nouvel appui »).
    public func playSelection() {
        guard let position = selection else { return }
        play(at: position)
    }

    public func stop(at position: GridPosition) {
        guard let pad = pad(at: position), case .audio = pad.content else { return }
        commands.yield(.stop(pad.id))
    }

    /// « Tout arrêter » (Échap).
    public func stopAll() {
        commands.yield(.stopAll)
    }

    /// Fader d'une colonne de la grille affichée, déplacé **à l'écran**. Niveau borné à 0…1. Un fader physique qui
    /// n'était plus à cette valeur se décroche (il reprend la main en la rejoignant, `moveHardwareFader`).
    public func setColumnLevel(_ column: Int, level: Double) {
        applyColumnLevel(column, level: level)
        syncHardwareFaders()
    }

    /// Fader **physique** déplacé (0…1). Tant qu'il n'a pas rejoint la valeur affichée (après un changement d'onglet, par
    /// exemple), il est ignoré : le volume ne saute pas. Renvoie `true` si la colonne a suivi.
    @discardableResult
    public func moveHardwareFader(column: Int, value: Double) -> Bool {
        guard (0..<PadGrid.size).contains(column), value.isFinite else { return false }
        let value = Gain.faderLevel(value)
        let applied = faderPickup.move(column: column, to: value, screen: currentGrid.columns[column].level)
        if applied { applyColumnLevel(column, level: value) }
        publishWaitingFaders()
        return applied
    }

    /// Positions déjà connues des faders physiques (gardées par la session d'une fenêtre à l'autre).
    func seedHardwareFaders(_ positions: [Int: Double]) {
        faderPickup.seed(positions)
        syncHardwareFaders()
    }

    private func applyColumnLevel(_ column: Int, level: Double) {
        guard (0..<PadGrid.size).contains(column) else { return }
        let level = Gain.faderLevel(level)
        show.grids[selectedGridIndex].columns[column].level = level
        onShowChange?(show)
        if show.grids[selectedGridIndex].columns[column].kind == .audio {
            commands.yield(.level(column: column, level: level))
        }
    }

    /// Les niveaux affichés ont pu changer : un fader physique n'est accroché que s'il y est encore.
    private func syncHardwareFaders() {
        faderPickup.sync(screenLevels: currentGrid.columns.map(\.level))
        publishWaitingFaders()
    }

    private func publishWaitingFaders() {
        let waiting = faderPickup.waiting
        if waiting != waitingFaders { waitingFaders = waiting }
    }

    /// Fader d'une colonne lumière déplacé **à l'écran** : règle le niveau et l'envoie à LightKey (CC du fader de la même
    /// colonne sur le contrôleur, via « Lalabob Lumière »). Un fader physique suit un autre chemin : `ControllerSession` le
    /// relaie à LightKey et `moveHardwareFader` règle l'écran (ADR 0006). Sans effet sur une colonne son (`setColumnLevel`).
    /// En mode d'appairage, bouger le fader le désigne aussi comme cible (`pairingFaderMoved`).
    public func setLightFader(column: Int, level: Double) {
        guard (0..<PadGrid.size).contains(column), currentGrid.columns[column].kind == .light else { return }
        let level = Gain.faderLevel(level)
        setColumnLevel(column, level: level)
        lightFaderHandler?(column, level)
        pairingFaderMoved(column: column)
    }

    /// Numéro de CC que LightKey reçoit pour le fader de cette colonne lumière (celui du contrôleur connu, ou de l'APC
    /// mini mk2 pour un contrôleur sans fader) ; `nil` si aucun contrôleur n'est connu ou si la colonne n'est pas lumière.
    public func lightFaderCC(forColumn column: Int) -> Int? {
        guard (0..<PadGrid.size).contains(column), currentGrid.columns[column].kind == .light,
            let model = connectedController ?? lastControllerModel,
            case .controlChange(_, let number, _)? = model.driver.faderEvent(column: column, value: 0)
                ?? ControllerModel.apcMiniMK2.driver.faderEvent(column: column, value: 0)
        else { return nil }
        return Int(number)
    }

    /// Remplace le spectacle ouvert (relecture d'un document).
    public func replaceShow(_ newShow: Show) {
        show = newShow
        onShowChange?(show)
        selectedGridIndex = 0
        selection = nil
        playback = [:]
        syncAudio()
        syncHardwareFaders()
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
    /// Verrouillé, la modification est refusée (avec un message), sauf si `allowedWhenLocked` : réglages de jeu
    /// (volume du pad, fondus) que la régie ajuste pendant le spectacle.
    @discardableResult
    func commit(_ actionName: String, allowedWhenLocked: Bool = false, _ change: (inout Show, Int) -> Bool) -> Bool {
        guard allowedWhenLocked || !refuseWhileLocked() else { return false }
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
        syncHardwareFaders()
        onShowChange?(show)

        guard let undoManager else { return }
        let isReplaying = undoManager.isUndoing || undoManager.isRedoing
        if !isReplaying { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated {
                // ⌘Z ne passe pas par `commit` : verrouillé, on refuse ici (l'étape d'annulation est perdue).
                guard !controller.refuseWhileLocked() else { return }
                controller.apply(previous, actionName: actionName)
            }
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
