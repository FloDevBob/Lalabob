import ControllerDrivers
import Foundation
import LalabobAudio
import LalabobMIDI
import LalabobModel
import Testing

@testable import LalabobEngine

/// Colonnes et pads « son et lumière » dans le moteur (fiche 06) : conversions de type (⌘Z, verrou, refus), jeu d'un pad mixte
/// (écran et contrôleur), routage des appuis, LED, appairage.
///
/// Grille d'essai : colonne 0 **mixte** (rangée 0 : son et lumière, 1 : son seul, 2 : cue seule, 3 : vide), colonne 1 son,
/// colonne 6 lumière. Notes de l'APC mini mk2 : (colonne, rangée) → (7 − rangée) × 8 + colonne.
@MainActor
@Suite("Colonnes mixtes", .serialized)
struct MixedColumnsTests {
    static let both = GridPosition(column: 0, row: 0)  // note 56
    static let soundOnly = GridPosition(column: 0, row: 1)  // note 48
    static let cueOnly = GridPosition(column: 0, row: 2)  // note 40
    static let empty = GridPosition(column: 0, row: 3)  // note 32
    static let audioCell = GridPosition(column: 1, row: 0)  // note 57
    static let lightCell = GridPosition(column: 6, row: 0)  // note 62

    struct Rig {
        let audio: RecordingAudioEngine
        let controller: ShowController
        let transport: FakeMIDITransport
        let runner: Task<Void, Never>
        let undo: UndoManager
    }

    private static func mixedShow() -> Show {
        var grid = PadGrid.empty(name: "G1")
        grid.columns[0] = Column.empty(name: "Scènes", kind: .mixed)
        grid[both] = Pad(
            title: "Aube", tint: .rose, audio: AudioClip(fileName: "coq.wav"),
            light: LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0), isPaired: true))
        grid[soundOnly] = Pad(title: "Applaudir", tint: .vert, audio: AudioClip(fileName: "bravo.wav"))
        grid[cueOnly] = Pad(title: "Noir", tint: .graphite, light: .blank)
        grid[audioCell] = Pad(title: "Pluie", tint: .ciel, audio: AudioClip(fileName: "pluie.wav"))
        grid[lightCell] = Pad(title: "Face", tint: .blanc, light: .blank)
        return Show(name: "S", grids: [grid])
    }

    private func makeRig(show: Show = MixedColumnsTests.mixedShow(), locked: Bool = false) -> Rig {
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            show: show, audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!, isLocked: locked)
        let undo = UndoManager()
        undo.groupsByEvent = false
        controller.undoManager = undo
        let transport = FakeMIDITransport()
        let session = ControllerSession(controller: controller, transport: transport)
        let runner = Task { await session.run() }
        return Rig(audio: audio, controller: controller, transport: transport, runner: runner, undo: undo)
    }

    private func plugAPC(_ rig: Rig) async {
        await rig.transport.setPorts(
            sources: [ControllerSessionTests.apcSource], destinations: [ControllerSessionTests.apcDestination])
        _ = await waitUntil { await rig.controller.connectedController == .apcMiniMK2 }
    }

    private func press(_ rig: Rig, note: UInt8) async {
        await rig.transport.receive([.noteOn(channel: 0, note: note, velocity: 100)], from: ControllerSessionTests.apcSource.id)
    }

    private func release(_ rig: Rig, note: UInt8) async {
        await rig.transport.receive([.noteOff(channel: 0, note: note, velocity: 0)], from: ControllerSessionTests.apcSource.id)
    }

    private func triggers(_ rig: Rig) async -> Int {
        await rig.audio.commands.filter { if case .trigger = $0 { true } else { false } }.count
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(250)) }

    // MARK: Type d'une colonne

    @Test("Son → Son et lumière : rien ne change ; une seule annulation")
    func columnWidenAndUndo() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        #expect(controller.conversionPlan(column: 1, to: .mixed).isLossless)
        #expect(controller.setColumnKind(1, to: .mixed))
        #expect(controller.show.grids[0].columns[1].kind == .mixed)
        #expect(controller.pad(at: Self.audioCell)?.title == "Pluie")
        rig.undo.undo()
        #expect(controller.show.grids[0].columns[1].kind == .audio)
        #expect(controller.pad(at: Self.audioCell)?.title == "Pluie")
    }

    @Test("Son et lumière → Son : un seul ⌘Z rend tout (pads, cues appairées, niveau)")
    func columnNarrowAndUndo() throws {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        let before = controller.show
        let plan = controller.conversionPlan(column: 0, to: .audio)
        #expect(plan.deletedPads.map(\.title) == ["Noir"])
        #expect(plan.padsLosingLight.map(\.title) == ["Aube"])

        #expect(controller.setColumnKind(0, to: .audio))
        #expect(controller.pad(at: Self.cueOnly) == nil)
        #expect(controller.pad(at: Self.both)?.light == nil)
        #expect(controller.pad(at: Self.both)?.audio?.fileName == "coq.wav")
        #expect(controller.pad(at: Self.soundOnly)?.title == "Applaudir")
        #expect(controller.currentGrid.columns[0].kind == .audio)
        try controller.show.validate()

        rig.undo.undo()
        #expect(controller.show == before)
    }

    @Test("Même type : aucune annulation enregistrée")
    func columnSameKind() {
        let rig = makeRig()
        rig.runner.cancel()
        #expect(!rig.controller.setColumnKind(0, to: .mixed))
        #expect(!rig.undo.canUndo)
    }

    @Test("Verrouillé : changer le type d'une colonne ou d'un pad est refusé")
    func lockedRefuses() {
        let rig = makeRig(locked: true)
        rig.runner.cancel()
        let before = rig.controller.show
        #expect(!rig.controller.setColumnKind(0, to: .audio))
        #expect(!rig.controller.setPadKind(at: Self.both, to: .audio))
        #expect(rig.controller.show == before)
        #expect(rig.controller.lockNotice != nil)
    }

    @Test("Un pad qui perd son son pendant sa lecture n'existe plus pour le moteur ; les autres sons continuent")
    func padLosingSoundLeavesTheEngine() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        rig.controller.setColumnKind(0, to: .light)  // coq.wav et bravo.wav n'ont plus de son
        try? await Task.sleep(for: .milliseconds(100))
        let counts = await rig.audio.commands.compactMap { command -> Int? in
            if case .configure(let count) = command { count } else { nil }
        }
        // Avant : 5 pads (Aube, Applaudir, Noir, Pluie, Face) ; après : « Aube » (cue seule) et « Noir » restent en colonne 0,
        // « Applaudir » est supprimé, « Pluie » et « Face » ne bougent pas.
        #expect(counts.last == 4)
        let stops = await rig.audio.commands.filter { if case .stopAll = $0 { true } else { false } }
        #expect(stops.isEmpty)  // aucun « Tout arrêter »
    }

    // MARK: Colonnes lumière communes (règle 5, reportée)

    private func sharedShow() -> Show {
        var show = Self.mixedShow()
        show.grids.append(.empty(name: "G2"))
        show.assignLightChannels(toGrids: [1])
        show.enableSharedLight(fromGrid: 0)
        return show
    }

    @Test("Colonnes lumière communes : une colonne commune ne change pas de type, et aucune colonne ne devient lumière")
    func sharedLightRefusals() {
        let rig = makeRig(show: sharedShow())
        rig.runner.cancel()
        let controller = rig.controller
        let before = controller.show
        #expect(controller.columnKindProblem(6, to: .audio) != nil)  // colonne commune
        #expect(controller.columnKindProblem(1, to: .light) != nil)  // deviendrait lumière
        #expect(controller.columnKindProblem(1, to: .mixed) == nil)  // son ↔ mixte reste local
        #expect(!controller.setColumnKind(6, to: .audio))
        #expect(controller.conversionNotice != nil)
        #expect(!controller.setColumnKind(1, to: .light))
        #expect(controller.show == before)
        controller.dismissConversionNotice()
        #expect(controller.conversionNotice == nil)
        #expect(controller.setColumnKind(1, to: .mixed))
    }

    // MARK: Type d'un pad

    @Test("Pad : Son → Son et lumière ajoute une cue ; ⌘Z la retire")
    func padSoundToMixed() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        #expect(controller.setPadKind(at: Self.soundOnly, to: .mixed))
        #expect(controller.pad(at: Self.soundOnly)?.kind == .mixed)
        #expect(controller.pad(at: Self.soundOnly)?.light?.isPaired == false)
        rig.undo.undo()
        #expect(controller.pad(at: Self.soundOnly)?.kind == .audio)
    }

    @Test("Pad : Lumière → Son et lumière attend son son")
    func padLightToMixed() {
        let rig = makeRig()
        rig.runner.cancel()
        #expect(rig.controller.setPadKind(at: Self.cueOnly, to: .mixed))
        #expect(rig.controller.pad(at: Self.cueOnly)?.awaitsSound == true)
    }

    @Test("Pad : Lumière → Son n'a rien à garder, le pad disparaît (le plan le dit avant)")
    func padLightToAudioDeletes() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        #expect(controller.conversionPlan(padAt: Self.cueOnly, to: .audio).deletedPads.map(\.title) == ["Noir"])
        #expect(controller.setPadKind(at: Self.cueOnly, to: .audio))
        #expect(controller.pad(at: Self.cueOnly) == nil)
        rig.undo.undo()
        #expect(controller.pad(at: Self.cueOnly)?.title == "Noir")
    }

    @Test("Pad : Son et lumière → Lumière perd le son (plan), garde la cue appairée")
    func padMixedToLight() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        #expect(controller.conversionPlan(padAt: Self.both, to: .light).padsLosingSound.map(\.title) == ["Aube"])
        #expect(controller.setPadKind(at: Self.both, to: .light))
        #expect(controller.pad(at: Self.both)?.audio == nil)
        #expect(controller.pad(at: Self.both)?.light?.isPaired == true)
    }

    @Test("Changer le type d'un pad est refusé hors colonne mixte, avec la raison")
    func padKindNeedsMixedColumn() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        #expect(!controller.setPadKind(at: Self.audioCell, to: .mixed))
        #expect(controller.conversionNotice?.contains("n'accepte que le son") == true)
        controller.dismissConversionNotice()
        #expect(!controller.setPadKind(at: Self.lightCell, to: .mixed))
        #expect(controller.conversionNotice?.contains("n'accepte que la lumière") == true)
        #expect(controller.pad(at: Self.audioCell)?.kind == .audio)
    }

    @Test("Un pad et une case vide : même type ou case vide, aucune annulation")
    func padNoOps() {
        let rig = makeRig()
        rig.runner.cancel()
        #expect(!rig.controller.setPadKind(at: Self.both, to: .mixed))
        #expect(!rig.controller.setPadKind(at: Self.empty, to: .audio))
        #expect(!rig.undo.canUndo)
    }

    // MARK: Placer, déplacer, déposer

    @Test("Une colonne mixte accepte un son, une cue et un pad mixte ; une colonne son refuse le pad mixte")
    func placementRules() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        let mixed = Pad(title: "M", tint: .rose, audio: AudioClip(fileName: "a.wav"), light: .blank)
        #expect(controller.place(mixed, at: Self.empty))
        #expect(!controller.place(mixed, at: GridPosition(column: 1, row: 4)))  // colonne son
        #expect(!controller.place(mixed, at: GridPosition(column: 6, row: 4)))  // colonne lumière
        #expect(controller.newLightCue(at: GridPosition(column: 0, row: 4)))
        // Déplacer un pad mixte vers une colonne son est refusé, vers une case de la colonne mixte est permis.
        #expect(!controller.movePad(from: Self.both, to: GridPosition(column: 1, row: 5)))
        #expect(controller.movePad(from: Self.both, to: GridPosition(column: 0, row: 5)))
    }

    private func tempSound(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "lalabob-mixed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    @Test("Glisser un son sur un pad lumière d'une colonne mixte : il devient son et lumière, rien n'est perdu")
    func dropOnCue() throws {
        let library = FileManager.default.temporaryDirectory.appending(path: "lalabob-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let audio = RecordingAudioEngine()
        let controller = ShowController(
            show: Self.mixedShow(), audio: audio, audioDirectory: library,
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        #expect(controller.dropAudioFile(try tempSound("orage.wav"), at: Self.cueOnly))
        let pad = try #require(controller.pad(at: Self.cueOnly))
        #expect(pad.kind == .mixed)
        #expect(pad.audio?.fileName == "orage.wav")
        #expect(pad.light != nil)
        #expect(pad.title == "Noir")  // le pad garde son titre, sa teinte, sa cue
        #expect(!pad.awaitsSound)
    }

    @Test("Glisser un son sur un pad « en attente de son » lui donne son son")
    func dropOnAwaiting() throws {
        var show = Self.mixedShow()
        show.grids[0][Self.cueOnly]?.awaitsSound = true
        let library = FileManager.default.temporaryDirectory.appending(path: "lalabob-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let controller = ShowController(
            show: show, audio: RecordingAudioEngine(), audioDirectory: library,
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        #expect(controller.dropAudioFile(try tempSound("orage.wav"), at: Self.cueOnly))
        let pad = try #require(controller.pad(at: Self.cueOnly))
        #expect(pad.audio?.fileName == "orage.wav")
        #expect(!pad.awaitsSound)
    }

    @Test("Glisser un son sur un pad son et lumière remplace le son et garde la cue ; sur un pad son, nouveau pad (comme avant)")
    func dropOnMixedAndOnSound() throws {
        let library = FileManager.default.temporaryDirectory.appending(path: "lalabob-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let controller = ShowController(
            show: Self.mixedShow(), audio: RecordingAudioEngine(), audioDirectory: library,
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        #expect(controller.dropAudioFile(try tempSound("nouveau.wav"), at: Self.both))
        let mixed = try #require(controller.pad(at: Self.both))
        #expect(mixed.audio?.fileName == "nouveau.wav")
        #expect(mixed.light?.isPaired == true)  // la cue appairée est intacte
        #expect(mixed.title == "Aube")

        #expect(controller.dropAudioFile(try tempSound("autre.wav"), at: Self.soundOnly))
        let replaced = try #require(controller.pad(at: Self.soundOnly))
        #expect(replaced.kind == .audio)
        #expect(replaced.title == "autre")  // nouveau pad prérempli, comme avant
    }

    @Test("Une colonne lumière refuse toujours un son")
    func lightColumnRefusesSound() throws {
        let library = FileManager.default.temporaryDirectory.appending(path: "lalabob-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let controller = ShowController(
            show: Self.mixedShow(), audio: RecordingAudioEngine(), audioDirectory: library,
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
        #expect(!controller.dropAudioFile(try tempSound("x.wav"), at: Self.lightCell))
        #expect(controller.importError != nil)
    }

    // MARK: Jouer à l'écran

    @Test("Double-clic sur un pad son et lumière : le son part, puis la cue (Note On, Note Off)")
    func screenPlayBoth() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.audition(at: Self.both)
        let expected: [MIDIEvent] = [.noteOn(channel: 0, note: 56, velocity: 127), .noteOff(channel: 0, note: 56, velocity: 0)]
        #expect(await waitUntil { await rig.transport.lighting == expected })
        #expect(await triggers(rig) == 1)
    }

    @Test("Nouvel appui, cue allumée : le son repart, la cue n'est pas renvoyée (« allumer seulement »)")
    func screenRetriggerTurnOnOnly() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        await rig.transport.receiveLightingFeedback([.noteOn(channel: 0, note: 56, velocity: 127)])
        #expect(await waitUntil { await rig.controller.lightState(at: Self.both) == .on })
        rig.controller.audition(at: Self.both)
        rig.controller.audition(at: Self.both)
        await settle()
        #expect(await triggers(rig) == 2)
        #expect(await rig.transport.lighting.isEmpty)
    }

    @Test("Cue éteinte ou inconnue : la cue part")
    func screenRetriggerOffOrUnknown() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        await rig.transport.receiveLightingFeedback([.noteOff(channel: 0, note: 56, velocity: 0)])
        #expect(await waitUntil { await rig.controller.lightState(at: Self.both) == .off })
        rig.controller.audition(at: Self.both)
        #expect(await waitUntil { await rig.transport.lighting.count == 2 })
    }

    @Test("Mode « basculer » : la cue part à chaque appui, même allumée")
    func screenRetriggerToggle() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.setLightRetrigger(at: Self.both, to: .toggle)
        await rig.transport.receiveLightingFeedback([.noteOn(channel: 0, note: 56, velocity: 127)])
        #expect(await waitUntil { await rig.controller.lightState(at: Self.both) == .on })
        rig.controller.audition(at: Self.both)
        #expect(await waitUntil { await rig.transport.lighting.count == 2 })
        #expect(await triggers(rig) == 1)
    }

    @Test("Pad son seul d'une colonne mixte : aucun message vers LightKey ; cue seule : aucun son")
    func screenPlaySingles() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.audition(at: Self.soundOnly)
        await settle()
        #expect(await triggers(rig) == 1)
        #expect(await rig.transport.lighting.isEmpty)
        rig.controller.audition(at: Self.cueOnly)
        #expect(await waitUntil { await rig.transport.lighting.count == 2 })
        #expect(await triggers(rig) == 1)
    }

    @Test("Verrouillé, jouer un pad son et lumière marche et le sélectionne")
    func lockedPlay() async {
        let rig = makeRig(locked: true)
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.audition(at: Self.both)
        #expect(await waitUntil { await rig.transport.lighting.count == 2 })
        #expect(rig.controller.selection == Self.both)
    }

    @Test("Tester la cue envoie la note sans lancer le son d'un pad son et lumière, même verrouillé")
    func testCueOnly() async {
        let rig = makeRig(locked: true)
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.testCue(at: Self.both)
        let expected: [MIDIEvent] = [.noteOn(channel: 0, note: 56, velocity: 127), .noteOff(channel: 0, note: 56, velocity: 0)]
        #expect(await waitUntil { await rig.transport.lighting == expected })
        #expect(await triggers(rig) == 0)
        rig.controller.testCue(at: Self.soundOnly)  // pas de cue : rien
        rig.controller.testCue(at: Self.empty)
        await settle()
        #expect(await rig.transport.lighting.count == 2)
    }

    @Test("Vider une colonne : une annulation, la colonne garde son type et son nom ; refusé verrouillé")
    func clearColumn() {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        #expect(controller.clearColumn(0))
        #expect(controller.currentGrid.columns[0].slots.allSatisfy { $0 == nil })
        #expect(controller.currentGrid.columns[0].kind == .mixed)
        #expect(controller.currentGrid.columns[0].name == "Scènes")
        #expect(!controller.clearColumn(0))  // déjà vide : rien à annuler
        rig.undo.undo()
        #expect(controller.pad(at: Self.both)?.title == "Aube")

        let locked = makeRig(locked: true)
        locked.runner.cancel()
        #expect(!locked.controller.clearColumn(0))
        #expect(locked.controller.pad(at: Self.both) != nil)
    }

    // MARK: Jouer au contrôleur

    @Test("Appui physique sur un pad son et lumière : le son part et la cue est relayée ; le Note Off suit le relâchement")
    func physicalBoth() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        await press(rig, note: 56)
        #expect(await waitUntil { await rig.transport.lighting == [.noteOn(channel: 0, note: 56, velocity: 127)] })
        #expect(await triggers(rig) == 1)
        await settle()
        #expect(await rig.transport.lighting.count == 1)  // pas de Note Off tant que le pad est tenu
        await release(rig, note: 56)
        let expected: [MIDIEvent] = [.noteOn(channel: 0, note: 56, velocity: 127), .noteOff(channel: 0, note: 56, velocity: 0)]
        #expect(await waitUntil { await rig.transport.lighting == expected })
    }

    @Test("Appui physique, cue déjà allumée : le son repart, aucune note, aucun Note Off au relâchement")
    func physicalRetrigger() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        await rig.transport.receiveLightingFeedback([.noteOn(channel: 0, note: 56, velocity: 127)])
        #expect(await waitUntil { await rig.controller.lightState(at: Self.both) == .on })
        await press(rig, note: 56)
        #expect(await waitUntil { await triggers(rig) == 1 })
        await release(rig, note: 56)
        await settle()
        #expect(await rig.transport.lighting.isEmpty)
    }

    @Test("Appui physique : son seul = le son ; cue seule = relais ; case vide = rien")
    func physicalSingles() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        await press(rig, note: 48)  // son seul
        #expect(await waitUntil { await triggers(rig) == 1 })
        #expect(await rig.transport.lighting.isEmpty)
        await release(rig, note: 48)

        await press(rig, note: 40)  // cue seule
        #expect(await waitUntil { await rig.transport.lighting == [.noteOn(channel: 0, note: 40, velocity: 127)] })
        #expect(await triggers(rig) == 1)
        await release(rig, note: 40)
        #expect(await waitUntil { await rig.transport.lighting.count == 2 })

        await press(rig, note: 32)  // case vide
        await release(rig, note: 32)
        await settle()
        #expect(await rig.transport.lighting.count == 2)
        #expect(await triggers(rig) == 1)
    }

    @Test("Colonnes son et lumière d'avant : une colonne son ne touche jamais la lumière, une colonne lumière jamais le son")
    func plainColumnsUnchanged() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        await press(rig, note: 57)  // colonne son
        #expect(await waitUntil { await triggers(rig) == 1 })
        #expect(await rig.transport.lighting.isEmpty)
        await release(rig, note: 57)
        await press(rig, note: 62)  // colonne lumière
        #expect(await waitUntil { await rig.transport.lighting == [.noteOn(channel: 0, note: 62, velocity: 127)] })
        #expect(await triggers(rig) == 1)
        await release(rig, note: 62)
    }

    @Test("Pause, stop et « Tout arrêter » ne touchent jamais la lumière")
    func stopsLeaveLightAlone() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.togglePause(at: Self.both)
        rig.controller.stop(at: Self.both)
        rig.controller.stopColumn(0)
        rig.controller.stopAll()
        await settle()
        #expect(await rig.transport.lighting.isEmpty)
    }

    @Test("Fader d'une colonne mixte : un volume (aucun CC vers LightKey) ; le bouton stop est allumé")
    func mixedColumnFader() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.setColumnLevel(0, level: 0.5)
        await rig.transport.receive([.controlChange(channel: 0, controller: 48, value: 64)], from: ControllerSessionTests.apcSource.id)
        await settle()
        #expect(await rig.transport.lighting.isEmpty)
        #expect(rig.controller.stopButtonColumns.contains(0))
        #expect(await rig.audio.commands.contains(.level(0, 0.5)))
    }

    // MARK: Appairage

    @Test("Appairage : l'appui sur un pad son d'une colonne mixte relaie la note sans jouer le son ; la réponse de LightKey lui ajoute la cue")
    func pairingOnSoundPad() async {
        let rig = makeRig()
        defer { rig.runner.cancel() }
        await plugAPC(rig)
        rig.controller.setPairingLights(true)

        await press(rig, note: 48)  // pad son seul de la colonne mixte
        #expect(await waitUntil { await rig.transport.lighting == [.noteOn(channel: 0, note: 48, velocity: 127)] })
        #expect(await triggers(rig) == 0)  // pas de son pendant l'appairage
        #expect(rig.controller.selection == Self.soundOnly)

        await rig.transport.receiveLightingFeedback([.noteOn(channel: 0, note: 48, velocity: 127)])
        #expect(await waitUntil { await rig.controller.isPaired(at: Self.soundOnly) })
        let pad = rig.controller.pad(at: Self.soundOnly)
        #expect(pad?.kind == .mixed)
        #expect(pad?.audio?.fileName == "bravo.wav")  // le son est gardé
        #expect(pad?.light?.isPaired == true)
        rig.undo.undo()
        #expect(rig.controller.pad(at: Self.soundOnly)?.kind == .audio)
    }

    @Test("Appairage : une case vide d'une colonne mixte devient un pad lumière ; la case libre suivante s'arme sur les pads à cue")
    func pairingOnEmptyAndNext() async {
        let rig = makeRig()
        rig.runner.cancel()
        let controller = rig.controller
        controller.setPairingLights(true)
        #expect(controller.isLightCell(Self.soundOnly))
        #expect(!controller.isLightCell(Self.audioCell))
        // Première cue non appairée : « Noir » (la cue de « Aube » est déjà appairée) ; une case vide de colonne mixte n'est pas proposée.
        #expect(controller.selection == Self.cueOnly)
        controller.selection = Self.empty
        controller.lightFeedbackArrived(at: Self.empty)
        #expect(controller.pad(at: Self.empty)?.kind == .light)
        #expect(controller.isPaired(at: Self.empty))
    }

    // MARK: LED

    @Test("LED d'un pad son et lumière : le son prime, sinon l'état de la cue")
    func ledStates() {
        let pad = Pad(title: "Aube", tint: .rose, audio: AudioClip(fileName: "a.wav"), light: .blank)
        var grid = PadGrid.empty(name: "G")
        grid.columns[0] = Column.empty(name: "M", kind: .mixed)
        grid[GridPosition(column: 0, row: 0)] = pad
        let position = GridPosition(column: 0, row: 0)
        func led(_ playback: [Pad.ID: PlaybackEvent], _ lights: [GridPosition: LightState]) -> LEDState? {
            LEDPlanner.states(for: grid, playback: playback, lightStates: lights)[position]
        }
        let playing = [pad.id: PlaybackEvent(pad: pad.id, state: .playing(startedAt: 0), duration: 10)]
        let paused = [pad.id: PlaybackEvent(pad: pad.id, state: .paused(elapsed: 1), duration: 10)]
        #expect(led([:], [:]) == .lit(.rose, .full))  // cue inconnue
        #expect(led([:], [position: .on]) == .pulsing(.rose))
        #expect(led([:], [position: .off]) == .lit(.rose, .quarter))
        #expect(led(playing, [position: .off]) == .pulsing(.rose))  // le son prime
        #expect(led(paused, [position: .on]) == .lit(.rose, .quarter))
    }
}
