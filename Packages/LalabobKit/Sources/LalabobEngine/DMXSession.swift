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
    /// Le banc d'essai DMX est ouvert : il a pris le boîtier, la sortie du spectacle attend (la console continue).
    public private(set) var isSuspendedForBench = false

    /// Interrupteur « Aperçu sur la barre » du panneau du bas : chaque réglage d'un pad lumière se voit tout de suite sur la
    /// barre. Mémorisé sur ce Mac, actif par défaut. Jamais verrouillé.
    public var isLivePreviewEnabled: Bool {
        didSet {
            defaults.set(isLivePreviewEnabled, forKey: Self.livePreviewKey)
            if !isLivePreviewEnabled { endPreview() }
        }
    }
    static let livePreviewKey = "dmxLivePreview"

    /// Lumière à rendre quand l'aperçu se termine, et le pad réglé (pour que ⌘Z et les modifications suivent).
    @ObservationIgnored private var previewBase: LightConsole.Snapshot?
    @ObservationIgnored private var previewPad: Pad.ID?
    @ObservationIgnored public private(set) weak var attachedController: ShowController?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @MainActor () -> Double
    /// Horloge de la lecture des sons (`ProcessInfo.systemUptime`), pour placer les temps du son sur `DMXClock`.
    @ObservationIgnored private let uptime: @MainActor () -> Double
    @ObservationIgnored private let makeTransport: @MainActor () -> any DMXTransport
    @ObservationIgnored private var transport: (any DMXTransport)?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var isShutDown = false
    @ObservationIgnored private let log = Logger(subsystem: "fr.lalabob.app", category: "dmx")

    public init(
        defaults: UserDefaults = .standard, now: @escaping @MainActor () -> Double = { DMXClock.now() },
        uptime: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime },
        makeTransport: @escaping @MainActor () -> any DMXTransport = { DMXOutput() }
    ) {
        self.defaults = defaults
        self.isLivePreviewEnabled = defaults.object(forKey: Self.livePreviewKey) as? Bool ?? true
        self.now = now
        self.uptime = uptime
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
        cancelPreview()
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

    /// « Essayer : 4 projecteurs en blanc » (Réglages du spectacle) : la console joue du blanc, sans pad. Mode Projecteurs seulement.
    public func testWhite() {
        guard var console else { return }
        console.play(
            .uniform(color: .white, intensity: 1, headCount: console.rig.profile.headCount), pad: nil, at: now())
        publish(console)
    }

    /// Boîtier choisi sur ce Mac (numéro de série), `nil` = le premier branché. Mémorisé avec celui du banc d'essai.
    public func selectPort(serialNumber: String?) {
        defaults.set(serialNumber, forKey: DMXTestBench.portKey)
        transport?.selectPort(serialNumber: serialNumber)
    }

    public var selectedPortSerial: String? { defaults.string(forKey: DMXTestBench.portKey) }

    // MARK: - Banc d'essai

    /// Le banc d'essai DMX s'ouvre : il prend la main sur le boîtier (décision du 27/11/2026). La sortie du spectacle
    /// s'arrête sans noir ; la console garde son état et les gestes continuent de la régler.
    public func suspendForBench() {
        guard !isSuspendedForBench else { return }
        isSuspendedForBench = true
        stopOutput(keepingConsole: true)
    }

    /// Le banc d'essai se ferme : la lumière du spectacle revient (même état, même fondu en cours).
    public func resumeAfterBench() {
        guard isSuspendedForBench else { return }
        isSuspendedForBench = false
        refresh()
    }

    private func handle(_ request: ShowController.DMXRequest) {
        if case .endPreview = request { return endPreview() }
        guard var console else { return }
        let time = now()
        switch request {
        case .preview(let padID, let look):
            guard isLivePreviewEnabled else { return }
            if previewBase == nil { previewBase = console.snapshot }
            previewPad = padID
            var shown = look
            shown.fadeIn = 0  // on règle à l'œil : pas de fondu
            console.play(shown, pad: nil, at: time)
        case .endPreview:
            return
        case .toggle(let pad):
            cancelPreview()
            let look = pad.light?.look ?? Self.fallbackLook(for: pad, headCount: console.rig.profile.headCount)
            if console.activePad == pad.id {
                console.fadeToBlack(duration: look.fadeIn, at: time)
            } else {
                console.play(look, pad: pad.id, at: time)
            }
        case .press(let pad, let force):
            cancelPreview()  // un appui ou un Noir pendant l'aperçu l'emporte
            let look = pad.light?.look ?? Self.fallbackLook(for: pad, headCount: console.rig.profile.headCount)
            if !force, console.activePad == pad.id {
                // Nouvel appui sur l'état en cours : « laisse allumé » ne fait rien, « allume ou éteint » éteint en fondu.
                guard pad.lightRetrigger == .toggle else { return }
                console.fadeToBlack(duration: look.fadeIn, at: time)
            } else {
                console.play(look, pad: pad.id, at: time)
            }
        case .blackout:
            cancelPreview()
            console.blackout(at: time)
        }
        publish(console)
    }

    /// L'aperçu est terminé (on quitte le pad) : retour en fondu à la lumière d'avant, avec les réglages faits entre-temps.
    private func endPreview() {
        guard var console, let base = previewBase else { return }
        cancelPreview()
        console.restore(base, fade: Self.previewReturnFade, at: now())
        syncLooks(&console)
        publish(console)
    }

    private func cancelPreview() {
        previewBase = nil
        previewPad = nil
    }

    /// Fondu du retour à la lumière d'avant, à la fin d'un aperçu.
    static let previewReturnFade = 0.5

    /// L'état joué suit le spectacle : un pad réglé (ou annulé par ⌘Z) pendant qu'il éclaire — ou pendant son aperçu — met la barre à jour.
    private func syncLooks(_ console: inout LightConsole) {
        guard let controller = attachedController else { return }
        if previewBase != nil {
            guard let id = previewPad, var committed = controller.committedLook(ofPad: id) else { return }
            committed.fadeIn = 0
            if console.activeLook != committed { console.replaceActiveLook(committed) }
        } else if let id = console.activePad, let committed = controller.committedLook(ofPad: id),
            console.activeLook != committed
        {
            console.replaceActiveLook(committed)
        }
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
            stopOutput(keepingConsole: false)
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
        updated.colorFader = level(.colors) ?? updated.colorFader
        updated.strobeOverride = level(.strobeSpeed).flatMap { $0 > 0 ? $0 : nil }
        // Le son qui donne le tempo : ses temps, ramenés de l'horloge des sons à celle de la lumière.
        let soundNow = uptime()
        updated.beatClock = controller.tempoSource(atUptime: soundNow).map {
            LightConsole.BeatClock(bpm: $0.bpm, origin: $0.beatUptime + (now() - soundNow))
        }
        syncLooks(&updated)
        publish(updated)
        startOutputIfNeeded()
    }

    private func publish(_ updated: LightConsole) {
        if console != updated { console = updated }
        transport?.setSource(updated)
        attachedController?.setDMXActivePad(updated.activePad)
    }

    private func startOutputIfNeeded() {
        guard transport == nil, !isSuspendedForBench, let console else { return }
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

    /// Arrête la sortie sans noir (passage en mode LightKey, banc d'essai) : la barre garde sa dernière lumière.
    private func stopOutput(keepingConsole: Bool) {
        if !keepingConsole { console = nil }
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

extension DMXStatus {
    /// Mot court pour la pastille « Projecteurs » de l'en-tête et les Réglages.
    public var headline: String {
        switch self {
        case .stopped: "Signal arrêté"
        case .noDevice: "Boîtier absent"
        case .connected: "Branché"
        case .failed: "En erreur"
        }
    }

    /// Une phrase d'aide quand quelque chose ne va pas ; `nil` si tout va bien.
    public var detail: String? {
        switch self {
        case .noDevice: "Branchez le boîtier USB-DMX : Lalabob le cherche chaque seconde."
        case .failed(_, let message): "\(message). Nouvel essai chaque seconde (une autre app utilise-t-elle le boîtier ?)."
        case .stopped, .connected: nil
        }
    }
}
