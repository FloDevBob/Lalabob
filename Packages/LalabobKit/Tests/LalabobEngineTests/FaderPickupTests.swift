import Foundation
import LalabobAudio
import LalabobModel
import Testing

@testable import LalabobEngine

/// Prise en main progressive des faders physiques : un fader qui ne correspond pas à l'écran (après un changement
/// d'onglet) ne fait rien tant qu'il n'a pas rejoint la valeur affichée, pour que le volume ne saute pas.
@Suite("Faders physiques : prise en main")
struct FaderPickupTests {
    @Test func aFaderFarFromTheScreenValueIsIgnored() {
        var pickup = FaderPickup()
        let hooked1 = pickup.move(column: 0, to: 0.2, screen: 0.8)
        #expect(!hooked1)
        let hooked2 = pickup.move(column: 0, to: 0.3, screen: 0.8)
        #expect(!hooked2)
        #expect(pickup.waiting == [0: 0.3])
    }

    @Test func aFaderHooksWhenItGetsCloseToTheScreenValue() {
        var pickup = FaderPickup()
        let hooked3 = pickup.move(column: 0, to: 0.7, screen: 0.8)
        #expect(!hooked3)
        let hooked4 = pickup.move(column: 0, to: 0.78, screen: 0.8)  // à 2 % : accroché
        #expect(hooked4)
        #expect(pickup.waiting.isEmpty)
    }

    @Test func theThresholdIsThreePercent() {
        var pickup = FaderPickup()
        let hooked5 = pickup.move(column: 0, to: 0.76, screen: 0.8)  // 4 % : trop loin
        #expect(!hooked5)
        let hooked6 = pickup.move(column: 0, to: 0.77, screen: 0.8)  // 3 % : accroché
        #expect(hooked6)
    }

    @Test func aFastMoveThatStepsOverTheScreenValueStillHooks() {
        var pickup = FaderPickup()
        let hooked7 = pickup.move(column: 0, to: 0.2, screen: 0.5)
        #expect(!hooked7)
        let hooked8 = pickup.move(column: 0, to: 0.9, screen: 0.5)  // a traversé 0,5 entre deux messages
        #expect(hooked8)
    }

    @Test func aFaderMovingAwayFromTheScreenValueDoesNotHook() {
        var pickup = FaderPickup()
        let hooked9 = pickup.move(column: 0, to: 0.2, screen: 0.8)
        #expect(!hooked9)
        let hooked10 = pickup.move(column: 0, to: 0.1, screen: 0.8)
        #expect(!hooked10)
        let hooked11 = pickup.move(column: 0, to: 0.0, screen: 0.8)
        #expect(!hooked11)
    }

    @Test func theFirstMessageOfAFaderHooksOnlyIfItIsClose() {
        var far = FaderPickup()
        let hooked12 = far.move(column: 3, to: 1, screen: 0.8)
        #expect(!hooked12)
        var near = FaderPickup()
        let hooked13 = near.move(column: 3, to: 0.81, screen: 0.8)
        #expect(hooked13)
    }

    @Test func onceHookedAFaderFollowsEverything() {
        var pickup = FaderPickup()
        let hooked14 = pickup.move(column: 0, to: 0.8, screen: 0.8)
        #expect(hooked14)
        // L'écran suit le fader : ensuite, même un grand écart est appliqué.
        let hooked15 = pickup.move(column: 0, to: 0.1, screen: 0.8)
        #expect(hooked15)
        let hooked16 = pickup.move(column: 0, to: 1, screen: 0.1)
        #expect(hooked16)
    }

    @Test func columnsAreIndependent() {
        var pickup = FaderPickup()
        let hooked17 = pickup.move(column: 0, to: 0.8, screen: 0.8)
        #expect(hooked17)
        let hooked18 = pickup.move(column: 1, to: 0.2, screen: 0.8)
        #expect(!hooked18)
        let hooked19 = pickup.move(column: 0, to: 0.5, screen: 0.8)
        #expect(hooked19)
        #expect(pickup.waiting == [1: 0.2])
    }

    @Test func changingTheScreenValueReleasesAHookedFader() {
        var pickup = FaderPickup()
        let hooked20 = pickup.move(column: 0, to: 0.8, screen: 0.8)
        #expect(hooked20)
        pickup.sync(screenLevels: [0.3] + Array(repeating: 0.8, count: 7))  // autre onglet : 0,3
        #expect(pickup.waiting == [0: 0.8])
        let hooked21 = pickup.move(column: 0, to: 0.81, screen: 0.3)  // pas de saut vers 0,81
        #expect(!hooked21)
        let hooked22 = pickup.move(column: 0, to: 0.31, screen: 0.3)  // il redescend et s'accroche
        #expect(hooked22)
    }

    @Test func aFaderAlreadyAtTheNewScreenValueStaysHooked() {
        var pickup = FaderPickup()
        let hooked23 = pickup.move(column: 0, to: 0.8, screen: 0.8)
        #expect(hooked23)
        pickup.sync(screenLevels: Array(repeating: 0.8, count: 8))  // même niveau sur l'autre onglet
        #expect(pickup.waiting.isEmpty)
        let hooked24 = pickup.move(column: 0, to: 0.5, screen: 0.8)
        #expect(hooked24)
    }

    @Test func aFaderWhoseOnscreenValueMeetsItReHooks() {
        var pickup = FaderPickup()
        let hooked25 = pickup.move(column: 0, to: 0.8, screen: 0.8)
        #expect(hooked25)
        pickup.sync(screenLevels: [0.2] + Array(repeating: 0.8, count: 7))
        #expect(pickup.waiting == [0: 0.8])
        pickup.sync(screenLevels: [0.79] + Array(repeating: 0.8, count: 7))  // la souris l'a rejoint
        #expect(pickup.waiting.isEmpty)
    }

    @Test func syncDoesNotInventPositions() {
        var pickup = FaderPickup()
        pickup.sync(screenLevels: Array(repeating: 0.8, count: 8))
        #expect(pickup.waiting.isEmpty)
        let hooked26 = pickup.move(column: 2, to: 0.1, screen: 0.8)  // aucun fader n'est accroché d'office
        #expect(!hooked26)
    }

    @Test func seededPositionsAreKnownButNotHookedUnlessClose() {
        var pickup = FaderPickup()
        pickup.seed([0: 0.8, 1: 0.2])
        pickup.sync(screenLevels: Array(repeating: 0.8, count: 8))
        #expect(pickup.waiting == [1: 0.2])  // le 0 est déjà à la valeur de l'écran
    }
}

/// Le même principe dans `ShowController` : pas de saut au changement d'onglet, pas d'ordre au moteur tant que
/// le fader n'est pas accroché, repère visible (`waitingFaders`) en attendant.
@MainActor
@Suite("Faders physiques : ShowController", .serialized)
struct HardwareFaderTests {
    private func makeController(audio: RecordingAudioEngine = RecordingAudioEngine()) -> ShowController {
        var show = Show(name: "S", grids: [.empty(name: "G1"), .empty(name: "G2")])
        show.grids[1].columns[0].level = 0.3
        show.grids[1].columns[6].level = 0.5
        return ShowController(
            show: show, audio: audio, audioDirectory: URL(filePath: "/tmp/lalabob-audio"),
            defaults: UserDefaults(suiteName: "lalabob-tests-\(UUID().uuidString)")!)
    }

    @Test func aPhysicalFaderFarFromTheScreenDoesNothing() async {
        let audio = RecordingAudioEngine()
        let controller = makeController(audio: audio)
        #expect(!controller.moveHardwareFader(column: 0, value: 0.1))
        #expect(controller.currentGrid.columns[0].level == 0.8)
        #expect(controller.waitingFaders == [0: 0.1])
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!(await audio.commands.contains(.level(0, 0.1))))
    }

    @Test func aPhysicalFaderHooksThenControlsTheColumn() async {
        let audio = RecordingAudioEngine()
        let controller = makeController(audio: audio)
        #expect(!controller.moveHardwareFader(column: 0, value: 0.5))
        #expect(controller.moveHardwareFader(column: 0, value: 0.79))
        #expect(controller.waitingFaders.isEmpty)
        #expect(controller.moveHardwareFader(column: 0, value: 0.2))
        #expect(controller.currentGrid.columns[0].level == 0.2)
        #expect(await waitUntil { await audio.commands.contains(.level(0, 0.2)) })
    }

    @Test func changingTabDoesNotMakeTheVolumeJump() async {
        let audio = RecordingAudioEngine()
        let controller = makeController(audio: audio)
        #expect(controller.moveHardwareFader(column: 0, value: 0.8))  // accroché sur l'onglet 1
        controller.selectGrid(at: 1)  // niveau 0,3 ; le fader est resté à 0,8
        #expect(controller.waitingFaders == [0: 0.8])

        #expect(!controller.moveHardwareFader(column: 0, value: 0.82))
        #expect(controller.currentGrid.columns[0].level == 0.3)  // pas de saut
        #expect(!controller.moveHardwareFader(column: 0, value: 0.5))
        #expect(controller.moveHardwareFader(column: 0, value: 0.32))  // il a rejoint 0,3
        #expect(controller.currentGrid.columns[0].level == 0.32)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!(await audio.commands.contains(.level(0, 0.82))))
    }

    @Test func aFaderAlreadyAtTheOtherTabLevelStaysHooked() {
        let controller = makeController()
        #expect(controller.moveHardwareFader(column: 1, value: 0.8))  // colonne 1 : 0,8 sur les deux onglets
        controller.selectGrid(at: 1)
        #expect(controller.waitingFaders.isEmpty)
        #expect(controller.moveHardwareFader(column: 1, value: 0.4))
    }

    @Test func movingTheFaderOnScreenReleasesThePhysicalOne() {
        let controller = makeController()
        #expect(controller.moveHardwareFader(column: 0, value: 0.8))
        controller.setColumnLevel(0, level: 0.2)  // à la souris
        #expect(controller.waitingFaders == [0: 0.8])
        #expect(!controller.moveHardwareFader(column: 0, value: 0.85))
        #expect(controller.currentGrid.columns[0].level == 0.2)
    }

    @Test func draggingTheOnscreenFaderUpToThePhysicalOneHooksItAgain() {
        let controller = makeController()
        #expect(controller.moveHardwareFader(column: 0, value: 0.8))
        controller.setColumnLevel(0, level: 0.2)
        controller.setColumnLevel(0, level: 0.79)
        #expect(controller.waitingFaders.isEmpty)
        #expect(controller.moveHardwareFader(column: 0, value: 0.3))
    }

    @Test func aLightFaderAlsoWaitsAndTellsItWasNotApplied() {
        let controller = makeController()
        controller.selectGrid(at: 1)  // colonne lumière 6 : 0,5
        #expect(!controller.moveHardwareFader(column: 6, value: 1))
        #expect(controller.currentGrid.columns[6].level == 0.5)
        #expect(controller.moveHardwareFader(column: 6, value: 0.51))
        #expect(controller.moveHardwareFader(column: 6, value: 1))
        #expect(controller.currentGrid.columns[6].level == 1)
    }

    @Test func seedingKnownPositionsShowsTheMarkersAtOnce() {
        let controller = makeController()
        controller.seedHardwareFaders([0: 0.8, 1: 0.2])
        #expect(controller.waitingFaders == [1: 0.2])  // 0 est déjà à la valeur de l'écran
    }

    @Test func invalidColumnsAreIgnored() {
        let controller = makeController()
        #expect(!controller.moveHardwareFader(column: 9, value: 0.5))
        #expect(!controller.moveHardwareFader(column: -1, value: 0.5))
        #expect(controller.waitingFaders.isEmpty)
    }

    @Test func replacingTheShowReleasesTheFaders() {
        let controller = makeController()
        #expect(controller.moveHardwareFader(column: 0, value: 0.8))
        var other = Show(name: "Autre", grids: [.empty(name: "G1")])
        other.grids[0].columns[0].level = 0.1
        controller.replaceShow(other)
        #expect(controller.waitingFaders == [0: 0.8])
    }
}
