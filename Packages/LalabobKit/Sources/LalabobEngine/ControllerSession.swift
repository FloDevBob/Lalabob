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

    /// Session rattachée à un seul spectacle (tests, aperçus).
    public convenience init(controller: ShowController, transport: any MIDITransport) {
        self.init(transport: transport)
        attach(controller)
    }

    public init(transport: any MIDITransport) {
        self.transport = transport

        // Une seule file d'envoi : les messages partent dans l'ordre où on les a produits.
        let (stream, continuation) = AsyncStream.makeStream(of: Outgoing.self, bufferingPolicy: .unbounded)
        self.outbox = continuation
        let log = self.log
        Task.detached {
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
        }
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
        lastLEDs = [:]
        pushLEDs()
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
            log.info("Contrôleur débranché : \(old.model.displayName)")
        }
        guard let found else { return }

        await transport.listen(to: found.source)
        let driver = found.model.driver
        active = Active(model: found.model, driver: driver, source: found.source, destination: found.destination)
        lastLEDs = [:]
        send(driver.connectionMessages)
        pushLEDs()
        attachedController?.setConnectedController(found.model)
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
            for event in message.events {
                switch active.driver.interpret(event) {
                case .padPressed(let position, let velocity) where velocity > 0:
                    attachedController?.pressFromController(at: position)
                case .columnFader(let column, let value):
                    lastHardwareFaders[column] = value
                    // Un fader pas encore accroché (autre onglet) est ignoré : le volume ne saute pas.
                    if attachedController?.moveHardwareFader(column: column, value: value) == true {
                        // Le fader physique a changé ce que LightKey croit : la prochaine valeur de l'écran doit repartir.
                        lastLightFaderEvents[column] = nil
                    }
                default:
                    break  // relâchement, messages inconnus
                }
            }
        }
    }

    // MARK: - Lumière

    /// Clic à l'écran sur un pad lumière : la note que le contrôleur aurait envoyée part sur
    /// « Lalabob Lumière », où LightKey a le même mapping que sur le contrôleur.
    private func sendLightPress(at position: GridPosition) {
        guard let model = active?.model ?? attachedController?.lastControllerModel, position.isValid else {
            log.notice("Clic lumière ignoré : aucun contrôleur connu pour choisir la note")
            return
        }
        let note = model.driver.note(for: position)
        let transport = self.transport
        let log = self.log
        Task.detached {
            do {
                try await transport.sendLighting([.noteOn(channel: 0, note: note, velocity: 127)])
                try await Task.sleep(for: .milliseconds(100))  // durée d'un appui bref
                try await transport.sendLighting([.noteOff(channel: 0, note: note, velocity: 0)])
            } catch {
                log.error("Envoi vers LightKey échoué : \(error.localizedDescription)")
            }
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
        guard let event = model.driver.faderEvent(column: column, value: level)
            ?? ControllerModel.apcMiniMK2.driver.faderEvent(column: column, value: level),
            lastLightFaderEvents[column] != event
        else { return }
        lastLightFaderEvents[column] = event
        lightingOutbox.yield(event)
    }

    // MARK: - LED

    private func watchLEDs() async {
        for await _ in Observations({ [weak self] in self?.attachedController?.ledStates }) { pushLEDs() }
    }

    /// Envoie au contrôleur les LED qui ont changé depuis le dernier envoi.
    private func pushLEDs() {
        guard let active, let desired = attachedController?.ledStates else { return }
        let changes = LEDPlanner.changes(from: lastLEDs, to: desired)
        guard !changes.isEmpty else { return }
        lastLEDs = desired
        send(active.driver.ledMessages(changes))
    }

    private func send(_ events: [MIDIEvent]) {
        guard let active, !events.isEmpty else { return }
        outbox.yield(Outgoing(destination: active.destination, events: events))
    }
}
