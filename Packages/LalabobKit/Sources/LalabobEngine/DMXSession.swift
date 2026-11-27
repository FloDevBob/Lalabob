import Foundation
import LalabobDMX
import LalabobModel
import Observation
import os

/// La lumière en DMX pour toute l'app (J14, étape 3, ADR 0012) : une seule barre, un seul boîtier, une seule console.
///
/// Comme `ControllerSession`, la session est rattachée au spectacle de la fenêtre active (`attach`). Si ce spectacle est en
/// mode **Projecteurs**, elle fait tourner la sortie DMX et lui donne la console (`LightConsole`) ; la sortie recalcule la
/// trame à chaque rafraîchissement sur son propre fil. En mode **LightKey**, la sortie est arrêtée (sans noir : la barre
/// garde sa lumière).
///
/// Changer de fenêtre ne change pas la lumière : la console reste celle de la session. Rien ici ne touche au son.
@MainActor
@Observable
public final class DMXSession {
    /// Fondu au noir le plus long à la fermeture de l'app : celle-ci n'attend pas indéfiniment (`AppLifecycle`).
    static let quitFadeLimit = 1.0

    /// État du boîtier (pastille « Projecteurs » de l'en-tête, étape 4).
    public private(set) var status: DMXStatus = .stopped
    /// La console en cours ; `nil` quand la fenêtre active n'est pas en mode Projecteurs.
    public private(set) var console: LightConsole?
    /// Boîtiers USB-DMX branchés.
    public private(set) var ports: [DMXPortInfo] = []

    @ObservationIgnored public private(set) weak var attachedController: ShowController?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @MainActor () -> Double
    @ObservationIgnored private let makeTransport: @MainActor () -> any DMXTransport
    @ObservationIgnored private var transport: (any DMXTransport)?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var isShutDown = false
    @ObservationIgnored private let log = Logger(subsystem: "fr.lalabob.app", category: "dmx")

    public init(
        defaults: UserDefaults = .standard, now: @escaping @MainActor () -> Double = { DMXClock.now() },
        makeTransport: @escaping @MainActor () -> any DMXTransport = { DMXOutput() }
    ) {
        self.defaults = defaults
        self.now = now
        self.makeTransport = makeTransport
    }

    // MARK: - Fenêtre active

    /// Rattache la session au spectacle d'une fenêtre (devenue active).
    public func attach(_ controller: ShowController) {
        guard attachedController !== controller else { return }
        if let old = attachedController { release(old) }
        attachedController = controller
        controller.dmxHandler = { [weak self] request in self?.handle(request) }
        controller.lightingChangeHandler = { [weak self] in self?.refresh() }
        refresh()
    }

    /// Détache le spectacle d'une fenêtre qui se ferme. La lumière en cours reste (la barre ne s'éteint pas).
    public func detach(_ controller: ShowController) {
        guard attachedController === controller else { return }
        release(controller)
        attachedController = nil
    }

    private func release(_ controller: ShowController) {
        controller.dmxHandler = nil
        controller.lightingChangeHandler = nil
        controller.setDMXActivePad(nil)
    }

    // MARK: - Gestes

    /// Allume ou coupe un projecteur (0 = le premier) en fondu, sur la lumière en cours, sans modifier le pad (mini-barre).
    public func setHead(_ index: Int, on: Bool) {
        guard var console else { return }
        console.setHead(index, on: on, at: now())
        publish(console)
    }

    public func toggleHead(_ index: Int) {
        guard let console else { return }
        setHead(index, on: !console.isHeadOn(index))
    }

    /// Boîtier choisi sur ce Mac (numéro de série), `nil` = le premier branché. Mémorisé avec celui du banc d'essai.
    public func selectPort(serialNumber: String?) {
        defaults.set(serialNumber, forKey: DMXTestBench.portKey)
        transport?.selectPort(serialNumber: serialNumber)
    }

    public var selectedPortSerial: String? { defaults.string(forKey: DMXTestBench.portKey) }

    private func handle(_ request: ShowController.DMXRequest) {
        guard var console else { return }
        let time = now()
        switch request {
        case .press(let pad, let force):
            let look = pad.light?.look ?? Self.fallbackLook(for: pad, headCount: console.rig.profile.headCount)
            if !force, console.activePad == pad.id {
                // Nouvel appui sur l'état en cours : « laisse allumé » ne fait rien, « allume ou éteint » éteint en fondu.
                guard pad.lightRetrigger == .toggle else { return }
                console.fadeToBlack(duration: look.fadeIn, at: time)
            } else {
                console.play(look, pad: pad.id, at: time)
            }
        case .blackout:
            console.blackout(at: time)
        }
        publish(console)
    }

    /// Une cue sans état lumineux (créée pour LightKey) : les projecteurs à la couleur de son pad, en fondu par défaut.
    static func fallbackLook(for pad: Pad, headCount: Int) -> LightLook {
        LightLook.uniform(color: LightColor(approximating: pad.tint.spec.vivid), intensity: 1, headCount: headCount)
    }

    // MARK: - Synchronisation

    /// Relit le spectacle rattaché : mode, appareil, faders lumière de la grille affichée.
    func refresh() {
        guard !isShutDown, let controller = attachedController else { return }
        guard controller.isDMXLighting else {
            stopOutput()
            controller.setDMXActivePad(nil)
            return
        }
        var updated = console ?? LightConsole(rig: controller.show.lighting.rig)
        updated.rig = controller.show.lighting.rig
        let grid = controller.currentGrid
        let roles = DMXFaderRole.roles(for: grid)
        func level(_ role: DMXFaderRole) -> Double? {
            roles.first { $0.value == role }.map { grid.columns[$0.key].level }
        }
        updated.master = level(.general) ?? 1
        updated.colorShift = level(.colors) ?? 0
        updated.strobeOverride = level(.strobeSpeed).flatMap { $0 > 0 ? $0 : nil }
        publish(updated)
        startOutputIfNeeded()
    }

    private func publish(_ updated: LightConsole) {
        if console != updated { console = updated }
        transport?.setSource(updated)
        attachedController?.setDMXActivePad(updated.activePad)
    }

    private func startOutputIfNeeded() {
        guard transport == nil, let console else { return }
        let output = makeTransport()
        transport = output
        output.selectPort(serialNumber: selectedPortSerial)
        output.setSource(console)
        output.start()
        status = output.status
        ports = output.availablePorts()
        let updates = output.statusUpdates
        statusTask = Task { [weak self] in
            for await status in updates {
                guard let self else { return }
                self.status = status
                self.ports = output.availablePorts()
            }
        }
    }

    /// Arrête la sortie sans noir (passage en mode LightKey) : la barre garde sa dernière lumière.
    private func stopOutput() {
        console = nil
        guard let output = transport else { return }
        transport = nil
        statusTask?.cancel()
        statusTask = nil
        status = .stopped
        Task { await output.shutdown(finalFrame: nil) }
    }

    // MARK: - Fermeture

    /// À la fermeture de l'app : selon le réglage du spectacle, fondu au noir (au plus `quitFadeLimit`) puis trame noire
    /// répétée, ou lumière laissée telle quelle. Après cet appel, plus rien ne part.
    public func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        statusTask?.cancel()
        statusTask = nil
        guard let output = transport else { return }
        transport = nil
        guard var console, console.rig.onQuit == .fadeToBlack else {
            await output.shutdown(finalFrame: nil)
            status = .stopped
            return
        }
        let duration = console.isBlack ? 0 : min(console.rig.blackoutFade, Self.quitFadeLimit)
        let start = now()
        console.fadeToBlack(duration: duration, at: start)
        output.setSource(console)
        self.console = console
        if duration > 0 { try? await Task.sleep(for: .seconds(duration)) }
        await output.shutdown(finalFrame: console.frame(at: start + duration + 1))
        status = .stopped
        log.info("Sortie DMX fermée (fondu au noir)")
    }
}
