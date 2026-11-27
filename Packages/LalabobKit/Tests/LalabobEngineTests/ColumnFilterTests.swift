import Foundation
import LalabobAudio
import LalabobModel
import Testing

@testable import LalabobEngine

@MainActor
@Suite("Filtre de colonne : ShowController")
struct ColumnFilterControllerTests {
    private func makeController(_ audio: RecordingAudioEngine, show: Show = .new()) -> ShowController {
        ShowController(
            show: show, audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
    }

    /// Les commandes partent de façon asynchrone : on attend qu'il n'en arrive plus.
    private func settledCommands(of audio: RecordingAudioEngine) async -> [RecordingAudioEngine.Command] {
        _ = await waitUntil { await !audio.commands.isEmpty }
        var last = -1
        while await audio.commands.count != last {
            last = await audio.commands.count
            try? await Task.sleep(for: .milliseconds(80))
        }
        return await audio.commands
    }

    @Test func filterUpdatesTheShowAndTheEngine() async {
        let audio = RecordingAudioEngine()
        let controller = makeController(audio)

        controller.setColumnFilter(2, value: -0.6)
        #expect(controller.currentGrid.columns[2].filter == -0.6)
        let sent = await settledCommands(of: audio)
        #expect(sent.last == .filter(2, -0.6))
    }

    @Test func valuesAreClampedAndSnappedToNeutral() async {
        let audio = RecordingAudioEngine()
        let controller = makeController(audio)

        controller.setColumnFilter(1, value: 3)
        #expect(controller.currentGrid.columns[1].filter == 1)
        controller.setColumnFilter(1, value: .nan)
        #expect(controller.currentGrid.columns[1].filter == 0)
        controller.setColumnFilter(1, value: 0.02)  // tout près du centre : aimanté au neutre
        #expect(controller.currentGrid.columns[1].filter == 0)
        controller.setColumnFilter(12, value: 0.5)  // colonne inexistante
        let sent = await settledCommands(of: audio)
        #expect(!sent.contains(.filter(12, 0.5)))
        #expect(sent.last == .filter(1, 0))
    }

    @Test func lightColumnsHaveNoFilter() async {
        let audio = RecordingAudioEngine()
        let controller = makeController(audio)
        controller.setColumnFilter(6, value: 0.5)
        #expect(controller.currentGrid.columns[6].filter == 0)
        let sent = await settledCommands(of: audio)
        #expect(!sent.contains(.filter(6, 0.5)))
    }

    @Test func resetReturnsToNeutral() async {
        let audio = RecordingAudioEngine()
        let controller = makeController(audio)
        controller.filterResetDuration = 0  // sans glissé : tout de suite
        controller.setColumnFilter(0, value: 0.8)
        controller.resetColumnFilter(0)
        #expect(controller.currentGrid.columns[0].filter == 0)
        let sent = await settledCommands(of: audio)
        #expect(sent.last == .filter(0, 0))
    }

    @Test func filterStillWorksWhenLocked() async {
        // Comme le volume : on règle en jouant, cadenas fermé.
        let audio = RecordingAudioEngine()
        let controller = makeController(audio)
        controller.isLocked = true
        controller.setColumnFilter(3, value: -0.3)
        #expect(controller.currentGrid.columns[3].filter == -0.3)
        #expect(controller.lockNotice == nil)
    }

    @Test func switchingGridSendsItsFilters() async {
        var second = PadGrid.empty(name: "G2")
        second.columns[4].filter = 0.45
        let audio = RecordingAudioEngine()
        let controller = makeController(audio, show: Show(name: "S", grids: [.empty(name: "G1"), second]))

        controller.selectGrid(at: 1)
        let sent = await settledCommands(of: audio)
        #expect(sent.last(where: { if case .filter(4, _) = $0 { true } else { false } }) == .filter(4, 0.45))
        controller.selectGrid(at: 0)
        let back = await settledCommands(of: audio)
        #expect(back.last(where: { if case .filter(4, _) = $0 { true } else { false } }) == .filter(4, 0))
    }

    @Test func openingAShowSendsEveryAudioColumnFilter() async {
        var show = Show.new()
        show.grids[0].columns[5].filter = -0.25
        let audio = RecordingAudioEngine()
        _ = makeController(audio, show: show)
        let sent = await settledCommands(of: audio)
        #expect(sent.contains(.filter(5, -0.25)))
        #expect(!sent.contains { if case .filter(6, _) = $0 { true } else { false } })  // colonnes lumière : rien
    }

    @Test func changesAreReportedToTheDocument() {
        let audio = RecordingAudioEngine()
        let controller = makeController(audio)
        var reported: Show?
        controller.onShowChange = { reported = $0 }
        controller.setColumnFilter(0, value: -0.5)
        #expect(reported?.grids[0].columns[0].filter == -0.5)
    }

    // MARK: Retour progressif au neutre (double-clic)

    @Test("Double-clic : le filtre glisse vers le neutre en passant par des valeurs intermédiaires, sans revenir en arrière")
    func resetGlidesToNeutral() async {
        let audio = RecordingAudioEngine()
        let controller = makeController(audio)
        controller.filterResetDuration = 0.3
        controller.setColumnFilter(0, value: 0.8)
        var seen: [Double] = []
        controller.onShowChange = { seen.append($0.grids[0].columns[0].filter) }
        controller.resetColumnFilter(0)
        #expect(controller.currentGrid.columns[0].filter == 0.8, "rien ne saute au double-clic")
        #expect(await waitUntil { await controller.currentGrid.columns[0].filter == 0 })
        #expect(seen.contains { $0 > 0.1 && $0 < 0.7 }, "on passe par le milieu")
        #expect(zip(seen, seen.dropFirst()).allSatisfy { $0 >= $1 }, "toujours vers le neutre")
        let sent = await settledCommands(of: audio)
        #expect(sent.last == .filter(0, 0))
        #expect(sent.filter { if case .filter(0, _) = $0 { true } else { false } }.count > 4, "le son suit le glissé")
    }

    @Test("Retour progressif aussi depuis un passe-bas")
    func resetGlidesFromLowPass() async {
        let controller = makeController(RecordingAudioEngine())
        controller.filterResetDuration = 0.2
        controller.setColumnFilter(3, value: -1)
        controller.resetColumnFilter(3)
        #expect(
            await waitUntil {
                await MainActor.run {
                    let filter = controller.currentGrid.columns[3].filter
                    return filter > -1 && filter < 0
                }
            })
        #expect(await waitUntil { await controller.currentGrid.columns[3].filter == 0 })
    }

    @Test("Toucher le potard pendant le retour l'interrompt : la main reprend")
    func touchingTheKnobStopsTheGlide() async {
        let controller = makeController(RecordingAudioEngine())
        controller.filterResetDuration = 0.4
        controller.setColumnFilter(1, value: 0.9)
        controller.resetColumnFilter(1)
        _ = await waitUntil { await controller.currentGrid.columns[1].filter < 0.85 }
        controller.setColumnFilter(1, value: -0.5)
        try? await Task.sleep(for: .milliseconds(600))
        #expect(controller.currentGrid.columns[1].filter == -0.5)
    }

    @Test("Changer de grille pendant le retour : la grille de départ finit au neutre, l'autre ne bouge pas")
    func glideStaysOnItsGrid() async {
        var show = Show.new()
        show.grids.append(PadGrid.empty(name: "B"))
        show.grids[1].columns[1].filter = 0.6
        let controller = makeController(RecordingAudioEngine(), show: show)
        controller.filterResetDuration = 0.3
        controller.setColumnFilter(1, value: -0.7)
        controller.resetColumnFilter(1)
        controller.selectGrid(at: 1)
        #expect(await waitUntil { await controller.show.grids[0].columns[1].filter == 0 })
        #expect(controller.show.grids[1].columns[1].filter == 0.6)
    }

    @Test("Déjà au neutre : rien à faire, aucun envoi")
    func resetAtNeutralDoesNothing() async {
        var changes = 0
        let controller = makeController(RecordingAudioEngine())
        controller.onShowChange = { _ in changes += 1 }
        controller.resetColumnFilter(0)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(changes == 0)
    }

    @Test("Un réglage à la valeur actuelle (clic sans mouvement) n'interrompt pas le retour au neutre")
    func sameValueDoesNotStopTheGlide() async {
        let controller = makeController(RecordingAudioEngine())
        controller.filterResetDuration = 0.3
        controller.setColumnFilter(2, value: 0.8)
        controller.resetColumnFilter(2)
        _ = await waitUntil { await controller.currentGrid.columns[2].filter < 0.7 }
        controller.setColumnFilter(2, value: controller.currentGrid.columns[2].filter)
        #expect(await waitUntil { await controller.currentGrid.columns[2].filter == 0 })
    }

    @Test("Durée de plus d'une seconde (celle de l'app) : le retour va bien jusqu'au neutre")
    func longGlideReachesNeutral() async {
        let controller = makeController(RecordingAudioEngine())
        controller.filterResetDuration = 1.2
        controller.setColumnFilter(4, value: 0.9)
        controller.resetColumnFilter(4)
        #expect(await waitUntil(timeout: 3) { await controller.currentGrid.columns[4].filter == 0 })
    }
}
