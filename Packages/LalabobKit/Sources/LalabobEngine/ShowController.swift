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
    /// État des cues lumière d'après le retour de LightKey, par canal (1 à 16) puis par case. Chaque grille a son canal.
    private(set) var lightStatesByChannel: [Int: [GridPosition: LightState]] = [:]
    /// État des cues de la grille affichée : celles de son canal LightKey, et celles du canal commun pour les colonnes
    /// lumière communes.
    public var lightStates: [GridPosition: LightState] {
        if isDMXLighting { return dmxLightStates }
        let own = currentLightChannel.flatMap { lightStatesByChannel[$0] } ?? [:]
        guard let sharedLight = show.sharedLight else { return own }
        let shared = Set(sharedLight.columnIndices)
        var states = own.filter { !shared.contains($0.key.column) }
        for (position, state) in lightStatesByChannel[sharedLight.channel] ?? [:] where shared.contains(position.column) {
            states[position] = state
        }
        return states
    }
    public private(set) var outputDevices: [AudioOutputDevice] = []
    /// `nil` = sortie par défaut du système.
    public private(set) var selectedOutputUID: String?
    /// Dernier import de son raté, à montrer à l'utilisateur (`nil` si rien à signaler).
    public internal(set) var importError: String?
    /// Dernier changement de type refusé (colonne ou pad), avec la raison, à montrer à l'utilisateur (`nil` si rien à signaler).
    public internal(set) var conversionNotice: String?
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
    /// Glisser de morceaux depuis le panneau Apple Music : combien on en glisse (0 = aucun glisser en cours) et les cases où
    /// ils tomberaient, dans l'ordre (aperçu numéroté).
    public internal(set) var musicDragCount = 0
    /// Lecteur des pads Apple Music (un seul pour l'app, posé par la fenêtre). `nil` : les pads Music ne jouent pas.
    @ObservationIgnored public var musicPlayer: MusicPlaybackCoordinator?
    public internal(set) var musicDropPreview: [GridPosition] = []

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
    /// Lumière en DMX : les demandes à la console (appui, Noir), traitées par `DMXSession` quand cette fenêtre est active.
    @ObservationIgnored var dmxHandler: (@MainActor (DMXRequest) -> Void)?
    /// Ce qui règle la console a pu changer (mode, appareil, faders lumière, grille affichée) : `DMXSession` relit tout.
    @ObservationIgnored var lightingChangeHandler: (@MainActor () -> Void)?
    /// Lumière en DMX : le pad dont l'état est joué par la console (`nil` : noir). Lalabob *est* la console, l'état est
    /// connu ; la règle « jamais d'état allumé déduit d'un envoi » reste celle de LightKey.
    public private(set) var dmxActivePad: Pad.ID?
    /// Tempo détecté de chaque son, par nom de fichier (étape 3b) ; absent = pas encore analysé ou illisible.
    public internal(set) var detectedTempos: [String: TempoEstimate] = [:]
    /// Analyse du tempo des sons, en arrière-plan (posée par la fenêtre). `nil` : pas d'analyse (tests, aperçus).
    @ObservationIgnored public var tempoAnalyzer: (any TempoAnalyzing)? {
        didSet { analyzeTempos() }
    }
    @ObservationIgnored var tempoRequested: Set<String> = []
    /// Rang de lancement des sons qui jouent (le plus grand = le dernier lancé), pour le tempo de la lumière.
    @ObservationIgnored var launchOrder: [Pad.ID: Int] = [:]
    @ObservationIgnored var launchCounter = 0
    /// « Taper le tempo » en cours : la case et les instants des appuis.
    @ObservationIgnored var taps: (position: GridPosition, times: [Double])?

    /// Une demande à la console DMX.
    enum DMXRequest: Equatable {
        /// Aperçu d'un réglage du pad (panneau du bas), sans fondu ; `endPreview` rend la lumière d'avant.
        case preview(Pad.ID, LightLook)
        case endPreview
        /// Les points du pad : allume cet état, ou l'éteint en fondu s'il est déjà celui qui éclaire.
        case toggle(Pad)
        /// Jouer l'état lumineux du pad ; `force` : même s'il est déjà joué (bouton Essayer), sans tenir compte de
        /// « nouvel appui ».
        case press(Pad, force: Bool)
        case blackout
    }

    private enum AudioCommand: Sendable {
        case configure(Show)
        case trigger(Pad.ID)
        case togglePause(Pad.ID)
        case stop(Pad.ID)
        case stopAll
        case level(column: Int, level: Double)
        case filter(column: Int, value: Double)
        case output(String?)
        case padGain(Pad.ID, Double)
        case seek(Pad.ID, TimeInterval)
        case attachExternal(AudioRingBuffer, Double, Int)
        case detachExternal
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
                    case .filter(let column, let value): await audio.setColumnFilter(column, value: value)
                    case .output(let uid): try await audio.setOutputDevice(uid: uid)
                    case .padGain(let id, let db): await audio.setPadGain(id, gainDB: db)
                    case .seek(let id, let elapsed): await audio.seek(id, to: elapsed)
                    case .attachExternal(let ring, let rate, let column): await audio.attachExternal(ring, sampleRate: rate, column: column)
                    case .detachExternal: await audio.detachExternal()
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

    /// La lumière est pilotée par Lalabob (projecteurs en DMX, ADR 0012) plutôt que par LightKey.
    public var isDMXLighting: Bool { show.lighting.mode == .dmx }

    /// État des pads lumière de la grille affichée en mode DMX : celui que joue la console est allumé, les autres éteints.
    private var dmxLightStates: [GridPosition: LightState] {
        var states: [GridPosition: LightState] = [:]
        for position in GridPosition.all {
            guard let pad = currentGrid[position], pad.light != nil else { continue }
            states[position] = pad.id == dmxActivePad ? .on : .off
        }
        return states
    }

    func setDMXActivePad(_ id: Pad.ID?) {
        if dmxActivePad != id { dmxActivePad = id }
    }

    /// Canal LightKey (1 à 16) de la grille affichée ; `nil` = « Sans canal » : rien ne part vers LightKey.
    public var currentLightChannel: Int? { currentGrid.lightChannel }

    /// Canal LightKey (1 à 16) d'une colonne de la grille affichée : le canal commun pour une colonne lumière commune, sinon
    /// celui de la grille ; `nil` = rien ne part.
    public func lightChannel(forColumn column: Int) -> Int? {
        show.lightChannel(grid: selectedGridIndex, column: column)
    }

    /// La grille qui utilise ce canal LightKey (pour le menu de l'onglet), `nil` s'il est libre.
    public func gridIndex(usingLightChannel channel: Int) -> Int? {
        show.grids.firstIndex { $0.lightChannel == channel }
    }

    public func selectGrid(at index: Int) {
        guard show.grids.indices.contains(index) else { return }
        selectedGridIndex = index
        syncColumnLevels()
        syncHardwareFaders()
        lightingChangeHandler?()
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

    /// « Tester la cue » (ampoule d'un pad, bouton Tester) : envoie la note de la cue à LightKey, **sans** jouer le son d'un pad son et
    /// lumière et sans tenir compte de « nouvel appui ». Marche aussi verrouillé (c'est du jeu).
    public func testCue(at position: GridPosition) {
        guard position.isValid, let pad = currentGrid[position], pad.light != nil else { return }
        if isDMXLighting { return dmxHandler?(.press(pad, force: true)) ?? () }
        lightPressHandler?(position)
    }

    /// Lance un pad : son, cue, ou les deux. Un pad son et lumière lance le son, puis sa cue — mais seulement si LightKey ne la dit
    /// pas déjà allumée (`LightRetrigger.turnOnOnly`, défaut) : LightKey bascule la cue à chaque note, relancer le son ne doit pas
    /// l'éteindre. `.toggle` l'envoie à chaque appui, comme un pad lumière.
    private func play(at position: GridPosition) {
        guard let pad = currentGrid[position] else { return }
        if pad.music != nil {
            musicPlayer?.press(pad, owner: self)
            if isLocked { selection = position }
            return
        }
        if pad.audio != nil {
            commands.yield(.trigger(pad.id))
            if isLocked { selection = position }
        }
        if pad.light != nil, shouldSendLight(for: pad, at: position) {
            sendLight(pad, at: position)
        }
    }

    /// La lumière d'un pad part : vers la console DMX ou vers LightKey, selon le mode.
    private func sendLight(_ pad: Pad, at position: GridPosition) {
        if isDMXLighting {
            dmxHandler?(.press(pad, force: false))
        } else {
            lightPressHandler?(position)
        }
    }

    /// La cue d'un pad doit-elle partir à cet appui ? Toujours pour un pad lumière seul (ou « en attente de son ») ; pour un pad
    /// son et lumière, selon « nouvel appui » : jamais sur une cue que LightKey dit allumée (l'état vient du retour, ADR 0006).
    func shouldSendLight(for pad: Pad, at position: GridPosition) -> Bool {
        guard pad.light != nil else { return false }
        guard pad.audio != nil else { return true }
        return pad.lightRetrigger == .toggle || lightState(at: position) != .on
    }

    /// Ce qu'un appui sur le contrôleur déclenche pour une case (la session MIDI s'en sert pour router l'appui).
    struct ControllerPress: Equatable, Sendable {
        /// Le son du pad part.
        var playsSound: Bool
        /// L'appui est relayé à LightKey (Note On à l'appui, Note Off au relâchement).
        var relaysLight: Bool
        /// Le morceau Apple Music du pad part (ou se met en pause, ou reprend).
        var playsMusic = false
        /// L'état lumineux du pad part vers la console DMX (mode Projecteurs).
        var playsLight = false
    }

    /// Routage d'un appui physique :
    /// - colonne **lumière** : relayé à LightKey, même sur une case vide (pour apprendre la note), jamais de son ;
    /// - colonne **son** : le son seul ;
    /// - colonne **mixte** : selon le pad (son seul, lumière seule, ou les deux) ; une case vide ne fait rien ;
    /// - en mode **appairage**, une colonne lumière ou mixte relaie toujours l'appui (c'est ainsi qu'on apprend la note à
    ///   LightKey) et ne joue aucun son.
    func controllerPress(at position: GridPosition) -> ControllerPress {
        guard position.isValid else { return ControllerPress(playsSound: false, relaysLight: false) }
        let kind = currentGrid.columns[position.column].kind
        if isDMXLighting {
            // Rien ne part vers LightKey : la lumière est jouée par la console, et une case vide ne fait rien.
            guard let pad = currentGrid[position] else { return ControllerPress(playsSound: false, relaysLight: false) }
            if pad.music != nil { return ControllerPress(playsSound: false, relaysLight: false, playsMusic: true) }
            return ControllerPress(
                playsSound: kind != .light && pad.audio != nil, relaysLight: false,
                playsLight: shouldSendLight(for: pad, at: position))
        }
        if kind == .light || (isPairingLights && !isLocked && kind == .mixed) {
            return ControllerPress(playsSound: false, relaysLight: true)
        }
        guard let pad = currentGrid[position] else { return ControllerPress(playsSound: false, relaysLight: false) }
        if pad.music != nil { return ControllerPress(playsSound: false, relaysLight: false, playsMusic: true) }
        return ControllerPress(playsSound: pad.audio != nil, relaysLight: shouldSendLight(for: pad, at: position))
    }

    /// Volume d'un pad pendant qu'on déplace la jauge : le moteur le suit tout de suite, y compris sur un son
    /// qui joue. Rien n'est écrit dans le spectacle ni dans l'historique : `setGain` valide la valeur finale
    /// (une seule annulation). Marche aussi verrouillé ; ignoré si la case n'a pas de son.
    public func previewGain(at position: GridPosition, _ decibels: Double) {
        guard let pad = pad(at: position), pad.audio != nil else { return }
        let clamped = AudioClip(fileName: "x").withGain(decibels).gainDB
        commands.yield(.padGain(pad.id, clamped))
    }

    /// Déplace la tête de lecture d'un pad (clic ou glisser sur la forme d'onde). `fileTime` : point cliqué, en secondes
    /// dans le fichier ; il est ramené à la partie élaguée. Le son joue de là, ou reste en pause là, ou démarre de là
    /// s'il était arrêté. Marche aussi verrouillé (le spectacle n'est pas modifié) ; ignoré si la case n'a pas de son.
    public func seek(at position: GridPosition, toFileTime fileTime: TimeInterval, fileDuration: TimeInterval) {
        guard let pad = pad(at: position), let clip = pad.audio else { return }
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

    public func dismissConversionNotice() {
        conversionNotice = nil
    }

    public func dismissLockNotice() {
        lockNotice = nil
    }

    /// Appui sur un pad Apple Music du contrôleur : lecture, pause ou reprise, quel que soit le mode de l'écran.
    func pressMusicFromController(at position: GridPosition) {
        guard let pad = pad(at: position), pad.music != nil else { return }
        musicPlayer?.press(pad, owner: self)
        if isLocked { selection = position }
    }

    /// Barre de position d'un pad Apple Music (panneau du bas) : déplace la lecture du morceau en cours. Marche verrouillé.
    public func seekMusic(at position: GridPosition, to seconds: TimeInterval) {
        guard let pad = pad(at: position), pad.music != nil else { return }
        musicPlayer?.seek(padID: pad.id, to: seconds)
    }

    /// Le lecteur Apple Music publie l'état d'un pad (même forme qu'un son de Lalabob : lueur, progression, LED).
    func applyMusicPlayback(_ event: PlaybackEvent) {
        if event.state == .idle { playback[event.pad] = nil } else { playback[event.pad] = event }
    }

    /// Pont audio : le son de Music joue dans la colonne de ce pad (grille où il se trouve), dans le moteur de cette fenêtre.
    func attachMusicBridge(_ ring: AudioRingBuffer, sampleRate: Double, pad: Pad.ID) {
        guard let column = show.grids.lazy.compactMap({ grid in grid.columns.firstIndex { $0.slots.contains { $0?.id == pad } } }).first
        else { return }
        commands.yield(.attachExternal(ring, sampleRate, column))
    }

    func detachMusicBridge() {
        commands.yield(.detachExternal)
    }

    /// Un message court à l'écran (bandeau), pour la lecture Apple Music (Music fermé, morceau introuvable…).
    func showMusicNotice(_ text: String) {
        lockNotice = text
    }

    /// Appui sur un pad du contrôleur : joue toujours, quel que soit le mode de l'écran.
    func pressFromController(at position: GridPosition) {
        guard let pad = pad(at: position), pad.audio != nil else { return }
        commands.yield(.trigger(pad.id))
        if isLocked { selection = position }
    }

    /// Les points d'un pad lumière (mode Projecteurs) : un clic allume l'état, un second l'éteint en fondu, quel que soit « Nouvel appui ».
    /// Marche verrouillé (c'est du jeu). Sans effet hors mode Projecteurs ou sur une case qui n'est pas une lumière.
    public func toggleLight(at position: GridPosition) {
        guard isDMXLighting, position.isValid, let pad = pad(at: position), pad.light != nil else { return }
        dmxHandler?(.toggle(pad))
    }

    /// Appui sur un pad lumière du contrôleur en mode DMX : son état part vers la console, quel que soit le mode de l'écran.
    func pressLightFromController(at position: GridPosition) {
        guard isDMXLighting, let pad = pad(at: position), pad.light != nil else { return }
        dmxHandler?(.press(pad, force: false))
        if isLocked { selection = position }
    }

    /// Noir (bouton de la mini-barre, menu Lumière, bouton rond d'une colonne lumière) : toute la barre s'éteint en fondu
    /// (« Fondu du noir » du spectacle). Mode DMX seulement ; marche verrouillé, c'est du jeu. Ne touche à aucun son.
    public func blackout() {
        guard isDMXLighting else { return }
        dmxHandler?(.blackout)
    }

    /// État d'une case lumière d'après LightKey (`.unknown` tant qu'il n'a rien dit).
    public func lightState(at position: GridPosition) -> LightState { lightStates[position] ?? .unknown }

    func setLightStates(_ states: [Int: [GridPosition: LightState]]) {
        guard states != lightStatesByChannel else { return }
        lightStatesByChannel = states
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
        if let pad = pad(at: position), pad.music != nil {
            if playback[pad.id]?.state.isActive == true { musicPlayer?.togglePause(pad, owner: self) }
            return
        }
        guard let pad = pad(at: position), pad.audio != nil else { return }
        commands.yield(.togglePause(pad.id))
    }

    /// Espace : sur le pad sélectionné, pause si le son joue, reprise s'il est en pause, lecture s'il est arrêté
    /// (ou cue lumière envoyée). Marche aussi verrouillé : c'est du jeu, pas de l'édition.
    public func togglePlaybackOfSelection() {
        guard let position = selection, let pad = pad(at: position) else { return }
        if pad.music != nil {  // un morceau : pause / reprise ; arrêté, il démarre
            musicPlayer?.togglePause(pad, owner: self)
            return
        }
        if pad.audio != nil, playback[pad.id]?.state.isActive == true {
            commands.yield(.togglePause(pad.id))
        } else {
            play(at: position)
        }
    }

    /// Bouton lecture / stop d'un pad son : arrête un son qui joue, reprend un son en pause, lance un son à l'arrêt.
    /// Marche aussi verrouillé (c'est du jeu). Sans effet sur une case vide ou une cue lumière.
    public func togglePlayStop(at position: GridPosition) {
        if let pad = pad(at: position), pad.music != nil { return play(at: position) }  // un morceau : lecture / stop (ou reprise s'il est en pause)
        guard let pad = pad(at: position), pad.audio != nil else { return }
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
        if let pad = pad(at: position), pad.music != nil { return musicPlayer?.stop(padID: pad.id) ?? () }
        guard let pad = pad(at: position), pad.audio != nil else { return }
        commands.yield(.stop(pad.id))
    }

    /// Arrête tous les sons de cette colonne **de la grille affichée** (joués ou en pause), avec le fondu d'arrêt habituel.
    /// Sans effet sur une colonne lumière ou une colonne sans son qui joue. Marche aussi verrouillé : c'est du jeu.
    public func stopColumn(_ column: Int) {
        guard (0..<PadGrid.size).contains(column) else { return }
        if currentGrid.columns[column].kind == .light {
            blackout()  // mode DMX : le bouton rond d'une colonne lumière est le Noir (sans effet avec LightKey)
            return
        }
        if currentGrid.columns[column].kind == .music {
            // Le morceau en cours, s'il vient de cette colonne : fondu de sortie.
            for case let pad? in currentGrid.columns[column].slots where pad.id == musicPlayer?.currentPad {
                musicPlayer?.stop(padID: pad.id)
            }
            return
        }
        guard currentGrid.columns[column].kind.hasAudio else { return }
        for case let pad? in currentGrid.columns[column].slots where playback[pad.id] != nil {
            commands.yield(.stop(pad.id))
        }
    }

    /// Colonnes dont le bouton « stop » est actif : les colonnes son de la grille affichée ; en mode DMX, aussi les colonnes
    /// lumière, dont le bouton fait le Noir (avec LightKey, elles n'en ont pas).
    /// Le bouton de l'interface et la LED rouge du contrôleur suivent cet ensemble.
    public var stopButtonColumns: Set<Int> {
        let dmx = isDMXLighting
        return Set(
            currentGrid.columns.indices.filter {
                let kind = currentGrid.columns[$0].kind
                return kind.hasAudio || kind == .music || (dmx && kind == .light)
            })
    }

    /// « Tout arrêter » (Échap).
    public func stopAll() {
        commands.yield(.stopAll)
        musicPlayer?.stopAll()
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
        // Colonne Music : un fader seulement quand le son de Music passe par Lalabob (pont audio) ; sinon le mouvement est ignoré.
        guard currentGrid.columns[column].kind != .music || musicPlayer?.isBridgeEnabled == true else { return false }
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
        if show.isSharedLightColumn(column) { show.propagateSharedLight(from: selectedGridIndex) }
        if isDMXLighting { show.alignDMXFaders(from: selectedGridIndex, column: column) }
        onShowChange?(show)
        if show.grids[selectedGridIndex].columns[column].kind != .light {  // son, mixte, ou Music (pont audio)
            commands.yield(.level(column: column, level: level))
        } else {
            lightingChangeHandler?()  // mode DMX : le fader d'une colonne lumière règle la console (rôle de la colonne)
        }
    }

    /// Filtre DJ d'une colonne son de la grille affichée (potard de la carte de volume) : −1 passe-bas, 0 neutre, +1
    /// passe-haut (`FilterCurve`). Borné, et aimanté au neutre tout près du centre. Comme le volume, il se règle en jouant
    /// (actif cadenas fermé) et ne passe pas par ⌘Z ; il est enregistré avec le spectacle. Sans effet sur une colonne lumière.
    public func setColumnFilter(_ column: Int, value: Double) {
        guard (0..<PadGrid.size).contains(column), currentGrid.columns[column].kind != .light else { return }
        // Rien ne change (un clic sans mouvement sur le potard) : le retour au neutre en cours continue.
        guard FilterCurve.snapped(value) != currentGrid.columns[column].filter else { return }
        filterGlides.removeValue(forKey: FilterGlideKey(grid: currentGrid.id, column: column))?.cancel()  // la main reprend
        applyColumnFilter(column, value: value, inGrid: currentGrid.id)
    }

    /// Durée du retour au neutre d'un filtre (double-clic sur le potard). 0 = tout de suite.
    public var filterResetDuration: TimeInterval = 1.5

    /// Remet le filtre au neutre (double-clic sur le potard) **en glissant** pendant `filterResetDuration` : le son s'ouvre
    /// doucement et l'aiguille du potard suit. Toucher le potard pendant le glissé l'interrompt. Changer de grille ne l'arrête
    /// pas : la grille de départ finit au neutre.
    public func resetColumnFilter(_ column: Int) {
        guard (0..<PadGrid.size).contains(column), currentGrid.columns[column].kind != .light else { return }
        let grid = currentGrid.id
        let key = FilterGlideKey(grid: grid, column: column)
        filterGlides.removeValue(forKey: key)?.cancel()
        let start = currentGrid.columns[column].filter
        guard start != 0 else { return }
        guard filterResetDuration > 0 else {
            applyColumnFilter(column, value: 0, inGrid: grid)
            return
        }
        let duration = filterResetDuration
        filterGlides[key] = Task { [weak self] in
            let began = ContinuousClock.now
            while !Task.isCancelled {
                let elapsed = ContinuousClock.now - began
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                let progress = min(1, seconds / duration)
                // Courbe en cosinus : départ et arrivée en douceur.
                let value = start * (1 + cos(Double.pi * progress)) / 2
                guard let self else { return }
                self.applyColumnFilter(column, value: progress >= 1 ? 0 : value, inGrid: grid)
                if progress >= 1 { break }
                try? await Task.sleep(for: .milliseconds(30))  // ~33 pas par seconde, comme un glisser à la souris
            }
            if !Task.isCancelled { self?.filterGlides[key] = nil }
        }
    }

    private struct FilterGlideKey: Hashable {
        let grid: PadGrid.ID
        let column: Int
    }

    /// Un retour au neutre en cours par colonne et par grille.
    @ObservationIgnored private var filterGlides: [FilterGlideKey: Task<Void, Never>] = [:]

    /// Écrit le filtre d'une colonne de la grille `gridID` ; le moteur ne le reçoit que si c'est la grille affichée (les autres
    /// lui sont renvoyées au changement d'onglet).
    private func applyColumnFilter(_ column: Int, value: Double, inGrid gridID: PadGrid.ID) {
        guard let index = show.grids.firstIndex(where: { $0.id == gridID }),
            show.grids[index].columns[column].kind != .light
        else { return }
        let value = FilterCurve.snapped(value)
        guard show.grids[index].columns[column].filter != value else { return }
        show.grids[index].columns[column].filter = value
        onShowChange?(show)
        if index == selectedGridIndex { commands.yield(.filter(column: column, value: value)) }
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
        guard !isDMXLighting else { return }  // la console a suivi (`lightingChangeHandler`) ; rien ne part vers LightKey
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
        lightingChangeHandler?()
    }

    // MARK: - Sortie audio

    public func selectOutput(uid: String?) {
        selectedOutputUID = uid
        defaults.set(uid, forKey: Self.outputDefaultsKey)
        commands.yield(.output(uid))
        musicPlayer?.outputChanged(to: uid, owner: self)  // pont audio : la capture suit l'horloge de la nouvelle sortie
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
            noteLaunch(event, previous: playback[event.pad]?.state)
            defer { if isDMXLighting { lightingChangeHandler?() } }  // le son qui donne le tempo a pu changer
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
        guard change(&updated, selectedGridIndex) else { return false }
        // Colonnes lumière communes : la modification faite dans la grille affichée vaut pour toutes les grilles.
        if !updated.grids.isEmpty { updated.propagateSharedLight(from: min(selectedGridIndex, updated.grids.count - 1)) }
        guard updated != show else { return false }
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
        lightingChangeHandler?()

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
        analyzeTempos()
    }

    /// Niveaux et filtres de la grille affichée vers le moteur (ouverture, changement d'onglet, annulation).
    private func syncColumnLevels() {
        for (index, column) in currentGrid.columns.enumerated() where column.kind != .light {
            commands.yield(.level(column: index, level: column.level))
            commands.yield(.filter(column: index, value: column.filter))
        }
    }

    deinit {
        commands.finish()  // libère le moteur audio de cette fenêtre
    }
}
