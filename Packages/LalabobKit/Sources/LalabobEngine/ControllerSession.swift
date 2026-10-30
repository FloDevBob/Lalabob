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
@MainActor
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

    private let controller: ShowController
    private let transport: any MIDITransport
    private let outbox: AsyncStream<Outgoing>.Continuation
    private let log = Logger(subsystem: "fr.lalabob.app", category: "midi")
    private var active: Active?
    private var lastLEDs: [GridPosition: LEDState] = [:]

    public init(controller: ShowController, transport: any MIDITransport) {
        self.controller = controller
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
    }

    /// À lancer une fois (`.task`) ; s'arrête avec la tâche qui l'appelle.
    public func run() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.watchTopology() }
            group.addTask { await self.watchInput() }
            group.addTask { await self.watchLEDs() }
            group.addTask { await self.watchLightPresses() }
        }
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
            controller.setConnectedController(nil)
            log.info("Contrôleur débranché : \(old.model.displayName)")
        }
        guard let found else { return }

        await transport.listen(to: found.source)
        let driver = found.model.driver
        active = Active(model: found.model, driver: driver, source: found.source, destination: found.destination)
        lastLEDs = [:]
        send(driver.connectionMessages)
        pushLEDs()
        controller.setConnectedController(found.model)
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
                    controller.pressFromController(at: position)
                case .columnFader(let column, let value):
                    controller.setColumnLevel(column, level: value)
                default:
                    break  // relâchement, messages inconnus
                }
            }
        }
    }

    // MARK: - Lumière

    /// Clic à l'écran sur un pad lumière : la note que le contrôleur aurait envoyée part sur
    /// « Lalabob Lumière », où LightKey a le même mapping que sur le contrôleur.
    private func watchLightPresses() async {
        for await position in controller.lightPresses {
            guard let model = active?.model ?? controller.lastControllerModel, position.isValid else {
                log.notice("Clic lumière ignoré : aucun contrôleur connu pour choisir la note")
                continue
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
    }

    // MARK: - LED

    private func watchLEDs() async {
        for await _ in Observations({ [controller] in controller.ledStates }) { pushLEDs() }
    }

    /// Envoie au contrôleur les LED qui ont changé depuis le dernier envoi.
    private func pushLEDs() {
        guard let active else { return }
        let desired = controller.ledStates
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
