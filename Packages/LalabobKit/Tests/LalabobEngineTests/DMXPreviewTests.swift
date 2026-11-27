import Foundation
import LalabobDMX
import LalabobModel
import Testing

@testable import LalabobEngine

/// Aperçu en direct sur la barre (J14, étape 4e) : chaque réglage d'un pad lumière s'applique tout de suite, sans fondu ;
/// en quittant le pad, la barre revient en fondu à la lumière qui était en cours. Jamais verrouillé.
@MainActor
@Suite("Aperçu sur la barre")
struct DMXPreviewTests {
    let session = DMXSessionTests()
    let red0 = GridPosition(column: 6, row: 0)
    let blue1 = GridPosition(column: 6, row: 1)
    let green = LightColor(hue: 120, saturation: 1)

    func look(_ color: LightColor, fade: Double = 0.5) -> LightLook {
        var look = LightLook.uniform(color: color, intensity: 1, headCount: 4)
        look.fadeIn = fade
        return look
    }

    func head1(_ rig: DMXSessionTests.Rig, after seconds: Double = 0) -> [UInt8] {
        session.headRGB(rig.frame(after: seconds), head: 1)
    }

    @Test("L'aperçu s'applique tout de suite, sans fondu, et ne désigne aucun pad comme joué")
    func previewIsImmediate() {
        let rig = session.makeRig()
        rig.controller.previewLook(at: red0, look(green, fade: 10))
        #expect(head1(rig) == [0, 255, 0])
        #expect(rig.session.console?.activePad == nil)
        #expect(rig.controller.dmxActivePad == nil)
    }

    @Test("En quittant le pad, la barre revient en fondu à la lumière qui était en cours")
    func endRestoresInFade() {
        let rig = session.makeRig()
        rig.controller.audition(at: red0)
        rig.clock.time += 5
        #expect(head1(rig) == [255, 0, 0])
        rig.controller.previewLook(at: blue1, look(green))
        #expect(head1(rig) == [0, 255, 0])
        rig.controller.endLookPreview()
        #expect(head1(rig) == [0, 255, 0])  // le fondu de retour commence à peine
        let middle = head1(rig, after: 0.25)
        #expect(middle[0] > 0 && middle[0] < 255)
        #expect(head1(rig, after: 5) == [255, 0, 0])
        #expect(rig.session.console?.activePad == session.redPad.id)
    }

    @Test("Un appui pendant l'aperçu l'emporte : le retour ne vient pas l'écraser")
    func pressCancelsRestore() {
        let rig = session.makeRig()  // noir au départ
        rig.controller.previewLook(at: red0, look(green))
        rig.controller.audition(at: GridPosition(column: 6, row: 1))  // le pad bleu
        rig.controller.endLookPreview()
        rig.clock.time += 5
        #expect(head1(rig) == [0, 0, 255])
    }

    @Test("Verrouillé, en mode LightKey ou interrupteur coupé : aucun aperçu")
    func previewRefused() {
        let locked = session.makeRig(locked: true)
        locked.controller.previewLook(at: red0, look(green))
        #expect(head1(locked) == [0, 0, 0])

        let lightKey = session.makeRig(mode: .lightKey)
        lightKey.controller.previewLook(at: red0, look(green))
        #expect(lightKey.session.console == nil)

        let off = session.makeRig()
        off.session.isLivePreviewEnabled = false
        off.controller.previewLook(at: red0, look(green))
        #expect(head1(off) == [0, 0, 0])
    }

    @Test("Un état injouable n'est pas prévisualisé")
    func invalidNotPreviewed() {
        let rig = session.makeRig()
        rig.controller.previewLook(at: red0, LightLook.uniform(color: green, intensity: 1, headCount: 3))
        #expect(head1(rig) == [0, 0, 0])
    }

    @Test("Couper l'interrupteur pendant un aperçu rend la lumière d'avant")
    func switchOffEndsPreview() {
        let rig = session.makeRig()
        rig.controller.previewLook(at: red0, look(green))
        rig.session.isLivePreviewEnabled = false
        rig.clock.time += 5
        #expect(head1(rig) == [0, 0, 0])
    }

    @Test("L'interrupteur est mémorisé sur ce Mac")
    func switchPersists() {
        let defaults = UserDefaults(suiteName: "DMXPreviewTests-\(UUID().uuidString)")!
        let first = DMXSession(defaults: defaults)
        #expect(first.isLivePreviewEnabled)
        first.isLivePreviewEnabled = false
        #expect(!DMXSession(defaults: defaults).isLivePreviewEnabled)
    }

    @Test("Régler le pad qui joue : la barre suit, et garde le réglage en quittant le pad")
    func editingThePlayingPad() {
        let rig = session.makeRig()
        rig.controller.audition(at: red0)
        rig.clock.time += 5
        rig.controller.setLook(at: red0, to: look(green))
        #expect(head1(rig) == [0, 255, 0])
        rig.controller.endLookPreview()
        rig.clock.time += 5
        #expect(head1(rig) == [0, 255, 0])
        #expect(rig.session.console?.activePad == session.redPad.id)
    }

    @Test("⌘Z pendant l'aperçu : la barre revient avec le réglage annulé")
    func undoFollows() {
        let rig = session.makeRig()
        let undo = UndoManager()
        undo.groupsByEvent = false
        rig.controller.undoManager = undo
        rig.controller.setLook(at: red0, to: look(green))
        #expect(head1(rig) == [0, 255, 0])
        undo.undo()
        #expect(head1(rig) == [255, 0, 0])
    }

    @Test("Le pad qui joue et dont l'état est annulé : la console suit sans fondu parasite")
    func undoOnPlayingPad() {
        let rig = session.makeRig()
        let undo = UndoManager()
        undo.groupsByEvent = false
        rig.controller.undoManager = undo
        rig.controller.audition(at: red0)
        rig.clock.time += 5
        rig.controller.setLook(at: red0, to: look(green))
        rig.controller.endLookPreview()
        rig.clock.time += 5
        undo.undo()
        rig.clock.time += 5
        #expect(head1(rig) == [255, 0, 0])
    }
}
