import ControllerDrivers
import Foundation
import LalabobMIDI
import LalabobModel
import Observation
import os

/// Relie un contrôleur physique à l'app : le détecte, le met en mode Programmeur, traduit ses appuis et
/// ses faders en commandes, et tient ses LED à jour avec l'écran.
///
/// Débrancher le contrôleur n'interrompt jamais le son : la session oublie le contrôleur, rien d'autre.
/// À rebranchement, elle refait la connexion complète (mode Programmeur, toutes les LED).
///
/// Une seule session pour toute l'app : elle est rattachée au spectacle de la fenêtre active (`attach`).
/// Changer de fenêtre renvoie toutes les LED ; aucun son d'une autre fenêtre n'est arrêté.
@MainActor
@Observable
public final class ControllerSession {
    private struct Active {
        var model: ControllerModel
        var driver: any ControllerDriver
        var source: MIDIPortID
        var destination: MIDIPortID
    }

    private struct Outgoing: Sendable {
        var destination: MIDIPortID
        var events: [MIDIEvent]
    }

    /// Banc d'essai de l'appairage lumière (inactif tant que sa fenêtre est fermée).
    public let bench = LightingTestBench()
    /// Réglages de couleur des LED par famille de contrôleur (Launchpad, APC), mémorisés d'un lancement à l'autre.
    public private(set) var ledSettingsByFamily: [String: LEDSettings]
    @ObservationIgnored private let defaults: UserDefaults
    static let settingsDefaultsKey = "ledSettings"
    /// Le 9e fader de l'APC règle le volume d'Apple Music (préférence de ce Mac, comme l'étalonnage des LED ; activé par défaut).
    public private(set) var isMusicVolumeEnabled: Bool
    /// Dernier volume envoyé à Apple Music (0 à 100), `nil` tant que rien n'est parti.
    public private(set) var musicVolume: Int?
    public private(set) var musicStatus: MediaVolumeStatus = .notRunning
    static let musicVolumeKey = "musicVolumeEnabled"
    @ObservationIgnored private var volumeRelay: MediaVolumeRelay?
    /// Le spectacle qui reçoit les appuis et dont les LED reflètent la grille.
    public private(set) var attachedController: ShowController?
    @ObservationIgnored private let transport: any MIDITransport
    @ObservationIgnored private let outbox: AsyncStream<Outgoing>.Continuation
    /// File d'envoi vers « Lalabob Lumière » pour les faders (l'ordre des valeurs compte : la dernière doit gagner).
    @ObservationIgnored private let lightingOutbox: AsyncStream<MIDIEvent>.Continuation
    @ObservationIgnored private var lastLightFaderEvents: [Int: MIDIEvent] = [:]
    /// Dernière position connue de chaque fader physique, gardée d'une fenêtre à l'autre (prise en main progressive).
    @ObservationIgnored private var lastHardwareFaders: [Int: Double] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "fr.lalabob.app", category: "midi")
    @ObservationIgnored private var active: Active?
    @ObservationIgnored private var lastLEDs: [GridPosition: LEDState] = [:]
    /// Boutons « stop » déjà envoyés au contrôleur (`nil` : rien d'envoyé depuis la connexion).
    @ObservationIgnored private var lastStopColumns: Set<Int>?
    /// Shift tenu (APC) : les boutons de scène visent les grilles 9 à 16.
    @ObservationIgnored private var shiftHeld = false
    @ObservationIgnored private var lastGridButtons: [MIDIEvent]?
    /// La tâche qui vide la file d'envoi vers le contrôleur (on l'attend à la fermeture, voir `shutdown`).
    @ObservationIgnored private var outboxTask: Task<Void, Never>?
    @ObservationIgnored private var isShutDown = false
    /// Dernier état connu de chaque cue lumière (retour de LightKey), par canal (1 à 16) puis par case ; partagé par tous
    /// les spectacles ouverts. Chaque grille a son canal : la grille affichée ne lit que le sien.
    @ObservationIgnored private var lightStates: [Int: [GridPosition: LightState]] = [:]
    /// Canal (0 à 15) sur lequel chaque appui physique relayé est parti : le Note Off du relâchement part sur le même, même
    /// si la grille a changé entre-temps.
    @ObservationIgnored private var relayedPresses: [GridPosition: UInt8] = [:]

    /// Session rattachée à un seul spectacle (tests, aperçus).
    public convenience init(
        controller: ShowController, transport: any MIDITransport, defaults: UserDefaults = .standard,
        mediaVolume: (any MediaVolumeControlling)? = nil
    ) {
        self.init(transport: transport, defaults: defaults, mediaVolume: mediaVolume)
        attach(controller)
    }

    public init(transport: any MIDITransport, defaults: UserDefaults = .standard, mediaVolume: (any MediaVolumeControlling)? = nil) {
        self.transport = transport
        self.defaults = defaults
        self.isMusicVolumeEnabled = defaults.object(forKey: Self.musicVolumeKey) as? Bool ?? true
        self.ledSettingsByFamily =
            (defaults.data(forKey: Self.settingsDefaultsKey)
            .flatMap { try? JSONDecoder().decode([String: LEDSettings].self, from: $0) } ?? [:])
            .mapValues(\.clamped)

        // Une seule file d'envoi : les messages partent dans l'ordre où on les a produits.
        let (stream, continuation) = AsyncStream.makeStream(of: Outgoing.self, bufferingPolicy: .unbounded)
        self.outbox = continuation
        let log = self.log
        self.outboxTask = Task.detached {
            for await message in stream {
                do { try await transport.send(message.events, to: message.destination) } catch {
                    log.error("Envoi MIDI échoué : \(error.localizedDescription)")
                }
            }
        }

        let (lightingStream, lightingContinuation) = AsyncStream.makeStream(of: MIDIEvent.self, bufferingPolicy: .unbounded)
        self.lightingOutbox = lightingContinuation
        Task.detached {
            for await event in lightingStream {
                do { try await transport.sendLighting([event]) } catch {
                    log.error("Envoi vers LightKey échoué : \(error.localizedDescription)")
                }
            }
        }
        bench.send = { [weak self] events in self?.sendToLightKey(events) }
        if let mediaVolume {
            self.volumeRelay = MediaVolumeRelay(target: mediaVolume, isEnabled: self.isMusicVolumeEnabled) { [weak self] status, percent in
                Task { @MainActor in self?.musicUpdated(status: status, percent: percent) }
            }
        }
    }

    @ObservationIgnored private var runner: Task<Void, Never>?

    /// Démarre la session pour toute la durée de l'app ; sans effet si elle tourne déjà.
    public func start() {
        guard runner == nil else { return }
        runner = Task { await run() }
    }

    /// Fait tourner la session ; s'arrête avec la tâche qui l'appelle (tests).
    public func run() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.watchTopology() }
            group.addTask { await self.watchInput() }
            group.addTask { await self.watchLEDs() }
            group.addTask { await self.watchStopButtons() }
            group.addTask { await self.watchGridButtons() }
            group.addTask { await self.watchLightingFeedback() }
        }
    }

    // MARK: - Étalonnage des LED

    /// Les réglages de couleur de ce contrôleur (ceux de sa famille ; le réglage conseillé tant qu'on n'y a pas touché).
    public func ledSettings(for model: ControllerModel) -> LEDSettings {
        ledSettingsByFamily[model.ledFamily] ?? .standard
    }

    /// Change les réglages de couleur d'un contrôleur : mémorisés, puis, s'il est branché, toutes ses LED sont renvoyées.
    public func setLEDSettings(_ settings: LEDSettings, for model: ControllerModel) {
        let settings = settings.clamped
        let previous = ledSettings(for: model)
        guard settings != previous else { return }
        ledSettingsByFamily[model.ledFamily] = settings
        if let data = try? JSONEncoder().encode(ledSettingsByFamily) { defaults.set(data, forKey: Self.settingsDefaultsKey) }
        if var current = active, current.model.ledFamily == model.ledFamily {
            current.driver = current.model.driver(settings: settings)
            active = current
            lastLEDs = [:]
            // En changeant de mode (palette ⇄ RVB), on repart d'une grille éteinte : un pad ne garde pas l'ancienne couleur.
            // Un simple réglage de curseur ne passe pas par là : pas de scintillement.
            if previous.usesRGB != settings.usesRGB { send(current.driver.connectionMessages) }
            pushLEDs()
        }
    }

    // MARK: - Fermeture

    /// À la fermeture de l'app : éteint toutes les LED du contrôleur (et ses boutons stop) et le remet dans son mode
    /// d'origine (le Launchpad quitte le mode Programmeur). Attend que tout soit parti ; ne coupe aucun son.
    /// Après cet appel, la session n'envoie plus rien au contrôleur.
    public func shutdown() async {
        guard !isShutDown else { return }
        if let active {
            outbox.yield(Outgoing(destination: active.destination, events: active.driver.shutdownMessages))
        }
        isShutDown = true
        outbox.finish()
        await outboxTask?.value
        // CoreMIDI remet les messages au pilote USB de façon asynchrone : on lui laisse un instant avant de quitter.
        if active != nil { try? await Task.sleep(for: .milliseconds(80)) }
    }

    // MARK: - Volume d'Apple Music

    /// Active ou coupe le pilotage du volume d'Apple Music par le 9e fader.
    public func setMusicVolumeEnabled(_ enabled: Bool) {
        isMusicVolumeEnabled = enabled
        defaults.set(enabled, forKey: Self.musicVolumeKey)
        if let volumeRelay { Task { await volumeRelay.setEnabled(enabled) } }
    }

    private func musicUpdated(status: MediaVolumeStatus, percent: Int?) {
        musicStatus = status
        if let percent { musicVolume = percent }
    }

    // MARK: - Fenêtre active

    /// Rattache la session au spectacle d'une fenêtre (devenue active). Les LED sont toutes renvoyées.
    public func attach(_ controller: ShowController) {
        guard attachedController !== controller else { return }
        attachedController?.lightPressHandler = nil
        attachedController?.lightFaderHandler = nil
        attachedController = controller
        controller.lightPressHandler = { [weak self] position in self?.sendLightPress(at: position) }
        controller.lightFaderHandler = { [weak self] column, level in self?.sendLightFader(column: column, level: level) }
        controller.setConnectedController(active?.model)
        controller.seedHardwareFaders(lastHardwareFaders)
        controller.setLightStates(lightStates)
        lastLEDs = [:]
        lastStopColumns = nil
        lastGridButtons = nil
        pushLEDs()
        pushStopButtons()
        pushGridButtons()
    }

    /// Détache le spectacle d'une fenêtre qui se ferme (sans effet si ce n'est pas le spectacle rattaché).
    public func detach(_ controller: ShowController) {
        guard attachedController === controller else { return }
        controller.lightPressHandler = nil
        controller.lightFaderHandler = nil
        controller.setConnectedController(nil)
        attachedController = nil
    }

    // MARK: - Branchements

    private func watchTopology() async {
        await refresh()
        for await _ in transport.changes { await refresh() }
    }

    private func refresh() async {
        let found = Self.findController(sources: await transport.sources(), destinations: await transport.destinations())
        if found?.source == active?.source, found?.destination == active?.destination { return }

        if let old = active {
            await transport.stopListening(to: old.source)
            active = nil
            lastLEDs = [:]
            lastHardwareFaders = [:]  // au rebranchement, on ne sait plus où sont les faders
            attachedController?.seedHardwareFaders([:])
            attachedController?.setConnectedController(nil)
            bench.setController(nil)
            log.info("Contrôleur débranché : \(old.model.displayName)")
        }
        guard let found else { return }

        await transport.listen(to: found.source)
        let driver = found.model.driver(settings: ledSettings(for: found.model))
        active = Active(model: found.model, driver: driver, source: found.source, destination: found.destination)
        lastLEDs = [:]
        lastStopColumns = nil
        lastGridButtons = nil
        send(driver.connectionMessages)
        pushLEDs()
        pushStopButtons()
        pushGridButtons()
        attachedController?.setConnectedController(found.model)
        bench.setController(found.model)
        log.info("Contrôleur connecté : \(found.model.displayName)")
    }

    /// Premier contrôleur reconnu parmi les ports : sa source (écoute) et sa destination (LED).
    /// Pour un Launchpad, le port « DAW » est écarté. Pur, donc testable.
    static func findController(
        sources: [MIDIPort], destinations: [MIDIPort]
    ) -> (model: ControllerModel, source: MIDIPortID, destination: MIDIPortID)? {
        for source in sources {
            guard let model = ControllerModel.detect(portName: source.name), model.isControlPort(named: source.name) else {
                continue
            }
            let candidates = destinations.filter {
                ControllerModel.detect(portName: $0.name) == model && model.isControlPort(named: $0.name)
            }
            // Même prise du périphérique (source et destination partagent leur groupe) ; sinon la première.
            let destination =
                candidates.first { source.groupID != 0 && $0.groupID == source.groupID } ?? candidates.first
            if let destination { return (model, source.id, destination.id) }
        }
        return nil
    }

    // MARK: - Entrées

    private func watchInput() async {
        for await message in transport.incoming {
            guard let active, message.source == active.source else { continue }
            bench.record(.fromController, message.events)
            for event in message.events {
                switch active.driver.interpret(event) {
                case .padPressed(let position, let velocity) where velocity > 0:
                    bench.setControllerPad(position, pressed: true)
                    // Une colonne lumière ne touche jamais au son ; une colonne mixte joue ce que son pad contient (son, cue,
                    // ou les deux) ; une colonne son ne touche jamais à la lumière. Sans spectacle rattaché : colonnes par défaut.
                    let press =
                        attachedController?.controllerPress(at: position)
                        ?? ShowController.ControllerPress(
                            playsSound: false, relaysLight: PadGrid.defaultLightColumns.contains(position.column))
                    if press.playsSound { attachedController?.pressFromController(at: position) }
                    if press.relaysLight { relayPad(position, pressed: true, driver: active.driver) }
                    attachedController?.pairingPress(at: position)
                case .padReleased(let position):
                    bench.setControllerPad(position, pressed: false)
                    // Le Note Off ne part que si le Note On a été relayé (`relayedPresses`) : on peut l'appeler pour toute case.
                    relayPad(position, pressed: false, driver: active.driver)
                case .columnStop(let column):
                    attachedController?.stopColumn(column)
                case .auxiliaryFader(let value):
                    if let volumeRelay { Task { await volumeRelay.faderMoved(to: value) } }
                case .gridSelect(let index):
                    attachedController?.selectGrid(at: index + (shiftHeld ? 8 : 0))
                case .gridStep(let delta):
                    if let controller = attachedController { controller.selectGrid(at: controller.selectedGridIndex + delta) }
                case .shift(let pressed):
                    shiftHeld = pressed
                    pushGridButtons()
                case .columnFader(let column, let value):
                    lastHardwareFaders[column] = value
                    // Un fader pas encore accroché (autre onglet) est ignoré : le volume ne saute pas.
                    attachedController?.moveHardwareFader(column: column, value: value)
                    // Sur une colonne lumière, LightKey reçoit la valeur physique (et la retient comme dernier envoi).
                    relayFader(column: column, value: value, driver: active.driver)
                    if isLightColumn(column) { attachedController?.pairingFaderMoved(column: column) }
                default:
                    break  // relâchement, messages inconnus
                }
            }
        }
    }

    // MARK: - Lumière

    /// Tout ce qui part vers LightKey passe ici : une seule file (l'ordre est garanti) et le banc d'essai le note.
    private func sendToLightKey(_ events: [MIDIEvent]) {
        bench.record(.toLightKey, events)
        for event in events { lightingOutbox.yield(event) }
    }

    /// Canal MIDI (0 à 15) d'une colonne lumière de la grille affichée : celui de la grille (fiche 01), ou le canal commun pour
    /// une colonne lumière commune (fiche 01b). `nil` = « Sans canal » : rien ne part. Sans spectacle rattaché, canal 1.
    private func lightMIDIChannel(column: Int) -> UInt8? {
        guard let controller = attachedController else { return 0 }
        return controller.lightChannel(forColumn: column).map { UInt8($0 - 1) }
    }

    /// Le même message sur un autre canal (les pilotes produisent tout sur le canal 1).
    private static func onChannel(_ channel: UInt8, _ event: MIDIEvent) -> MIDIEvent {
        switch event {
        case let .noteOn(_, note, velocity): .noteOn(channel: channel, note: note, velocity: velocity)
        case let .noteOff(_, note, velocity): .noteOff(channel: channel, note: note, velocity: velocity)
        case let .controlChange(_, controller, value): .controlChange(channel: channel, controller: controller, value: value)
        case .systemExclusive: event
        }
    }

    /// Canal (1 à 16) d'un message reçu de LightKey (`nil` pour un SysEx).
    private static func channel(of event: MIDIEvent) -> Int? {
        switch event {
        case let .noteOn(channel, _, _), let .noteOff(channel, _, _), let .controlChange(channel, _, _): Int(channel) + 1
        case .systemExclusive: nil
        }
    }

    /// LightKey n'écoute que Lalabob (ADR 0006) : l'appui physique sur une colonne lumière lui est relayé,
    /// Note On à l'appui et Note Off au relâchement réel, sur le canal de la grille affichée.
    private func relayPad(_ position: GridPosition, pressed: Bool, driver: any ControllerDriver) {
        guard position.isValid else { return }
        let note = driver.note(for: position)
        if pressed {
            guard let channel = lightMIDIChannel(column: position.column) else {
                log.notice("Appui lumière non relayé : la grille affichée est « Sans canal »")
                return
            }
            relayedPresses[position] = channel
            sendToLightKey([.noteOn(channel: channel, note: note, velocity: 127)])
        } else if let channel = relayedPresses.removeValue(forKey: position) {
            sendToLightKey([.noteOff(channel: channel, note: note, velocity: 0)])
        }
    }

    /// Fader physique d'une colonne lumière : le même CC part vers LightKey, sur le canal de la grille (une valeur
    /// inchangée n'est pas répétée).
    private func relayFader(column: Int, value: Double, driver: any ControllerDriver) {
        guard isLightColumn(column), let channel = lightMIDIChannel(column: column),
            let event = driver.faderEvent(column: column, value: value).map({ Self.onChannel(channel, $0) }),
            lastLightFaderEvents[column] != event
        else { return }
        lastLightFaderEvents[column] = event
        sendToLightKey([event])
    }

    private func isLightColumn(_ column: Int) -> Bool {
        if let grid = attachedController?.currentGrid, grid.columns.indices.contains(column) {
            return grid.columns[column].kind == .light
        }
        return PadGrid.defaultLightColumns.contains(column)
    }

    private func watchLightingFeedback() async {
        for await events in transport.lightingFeedback {
            bench.recordFeedback(events)
            // Les notes du retour sont celles du contrôleur : même disposition que pour les appuis.
            let driver = active?.driver ?? (attachedController?.lastControllerModel ?? .apcMiniMK2).driver
            var changed = false
            for event in events {
                // Un CC de retour sur le numéro d'un fader lumière : LightKey a reconnu ce fader (mode d'appairage).
                // Seul le canal de cette colonne, dans la grille affichée, concerne l'appairage en cours.
                if case .controlChange = event,
                    case .columnFader(let column, _)? = driver.interpret(event) ?? ControllerModel.apcMiniMK2.driver.interpret(event),
                    Self.channel(of: event) == attachedController?.lightChannel(forColumn: column)
                {
                    attachedController?.faderFeedbackArrived(column: column)
                }
                guard let (channel, position, state) = driver.lightFeedback(for: event) else { continue }
                if channel == attachedController?.lightChannel(forColumn: position.column) {
                    attachedController?.lightFeedbackArrived(at: position)  // mode d'appairage : la case cible répond
                }
                guard lightStates[channel]?[position] != state else { continue }
                lightStates[channel, default: [:]][position] = state  // le dernier message gagne : une rafale identique ne change rien
                changed = true
            }
            if changed { attachedController?.setLightStates(lightStates) }
        }
    }

    /// Clic à l'écran sur un pad lumière : la note que le contrôleur aurait envoyée part sur
    /// « Lalabob Lumière », où LightKey a le même mapping que sur le contrôleur.
    private func sendLightPress(at position: GridPosition) {
        guard let model = active?.model ?? attachedController?.lastControllerModel, position.isValid else {
            log.notice("Clic lumière ignoré : aucun contrôleur connu pour choisir la note")
            return
        }
        guard let channel = lightMIDIChannel(column: position.column) else {
            log.notice("Clic lumière ignoré : la grille affichée est « Sans canal »")
            return
        }
        let note = model.driver.note(for: position)
        sendToLightKey([.noteOn(channel: channel, note: note, velocity: 127)])
        Task {
            try? await Task.sleep(for: .milliseconds(100))  // durée d'un appui bref
            sendToLightKey([.noteOff(channel: channel, note: note, velocity: 0)])
        }
    }

    /// Fader d'une colonne lumière déplacé à l'écran : le CC que le contrôleur aurait envoyé part sur « Lalabob Lumière ».
    /// Un contrôleur sans fader (Launchpad) emprunte la correspondance de l'APC mini mk2, seul à en avoir ; sans aucun
    /// contrôleur connu, rien n'est envoyé (LightKey n'a rien à lier). Une valeur inchangée (sur 7 bits) n'est pas renvoyée.
    private func sendLightFader(column: Int, level: Double) {
        guard let model = active?.model ?? attachedController?.lastControllerModel else {
            log.notice("Fader lumière ignoré : aucun contrôleur connu pour choisir le CC")
            return
        }
        guard let channel = lightMIDIChannel(column: column) else {
            log.notice("Fader lumière ignoré : la grille affichée est « Sans canal »")
            return
        }
        guard let event = (model.driver.faderEvent(column: column, value: level)
            ?? ControllerModel.apcMiniMK2.driver.faderEvent(column: column, value: level)).map({ Self.onChannel(channel, $0) }),
            lastLightFaderEvents[column] != event
        else { return }
        lastLightFaderEvents[column] = event
        sendToLightKey([event])
    }

    // MARK: - LED

    private func watchStopButtons() async {
        for await _ in Observations({ [weak self] in self?.attachedController?.stopButtonColumns }) { pushStopButtons() }
    }

    /// Allume en rouge les boutons « stop » des colonnes son (APC mini mk2) ; ceux des colonnes lumière restent éteints.
    private func pushStopButtons() {
        guard let active, !isShutDown else { return }
        let columns = attachedController?.stopButtonColumns ?? []
        guard columns != lastStopColumns else { return }
        lastStopColumns = columns
        send(active.driver.stopButtonMessages(litColumns: columns))
    }

    private func watchGridButtons() async {
        for await _ in Observations({ [weak self] in (self?.attachedController?.selectedGridIndex, self?.attachedController?.show.grids.count) }) {
            pushGridButtons()
        }
    }

    /// Allume le bouton de la grille affichée (APC) ou les flèches possibles (Launchpad) ; ne renvoie que si ça change.
    private func pushGridButtons() {
        guard let active, !isShutDown, let controller = attachedController else { return }
        let messages = active.driver.gridButtonMessages(
            current: controller.selectedGridIndex, count: controller.show.grids.count, shiftHeld: shiftHeld)
        guard messages != lastGridButtons else { return }
        lastGridButtons = messages
        send(messages)
    }

    private func watchLEDs() async {
        for await _ in Observations({ [weak self] in self?.attachedController?.ledStates }) { pushLEDs() }
    }

    /// Envoie au contrôleur les LED qui ont changé depuis le dernier envoi.
    private func pushLEDs() {
        guard let active, !isShutDown, let desired = attachedController?.ledStates else { return }
        let changes = LEDPlanner.changes(from: lastLEDs, to: desired)
        guard !changes.isEmpty else { return }
        lastLEDs = desired
        send(active.driver.ledMessages(changes))
    }

    private func send(_ events: [MIDIEvent]) {
        guard let active, !events.isEmpty, !isShutDown else { return }
        outbox.yield(Outgoing(destination: active.destination, events: events))
    }
}
