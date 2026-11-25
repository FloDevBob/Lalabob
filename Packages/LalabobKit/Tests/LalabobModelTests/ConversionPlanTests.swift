import Foundation
import Testing

@testable import LalabobModel

/// Conversions de type (fiche 06) : une fonction de test par ligne des deux tableaux de la fiche. Élargir ne retire rien ;
/// restreindre retire ce qui ne rentre plus, et le plan le dit exactement.
@Suite("Plan de conversion")
struct ConversionPlanTests {
    private static let clip = AudioClip(fileName: "orage.wav", trimStart: 0.4, gainDB: -6)
    private static let pairedCue = LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 54), isPaired: true)

    private static func sound(_ title: String = "Orage") -> Pad {
        Pad(title: title, subtitle: "Ambiance", tint: .azur, ledIntensity: .half, audio: clip)
    }
    private static func cue(_ title: String = "Plein feu", paired: Bool = true) -> Pad {
        Pad(title: title, subtitle: "Cue", tint: .ambre, light: paired ? pairedCue : .blank)
    }
    private static func both(_ title: String = "Aube") -> Pad {
        Pad(title: title, subtitle: "Coq + lever", tint: .rose, audio: clip, light: pairedCue)
    }
    private static func waiting(_ title: String = "À venir") -> Pad {
        Pad(title: title, tint: .rose, light: pairedCue, awaitsSound: true)
    }

    /// Une colonne de 3 pads : son (0), lumière (1), son et lumière (2), le reste vide.
    private static func column(_ kind: ColumnKind, level: Double? = nil, filter: Double = 0, faderPaired: Bool = false) -> Column {
        var column = Column.empty(name: "Colonne", kind: kind)
        column.slots[0] = sound()
        column.slots[1] = cue()
        column.slots[2] = both()
        if let level { column.level = level }
        column.filter = filter
        column.isFaderPaired = faderPaired
        return column
    }

    // MARK: Colonnes (tableau 1)

    @Test("Son → Son et lumière : rien ne change, volume conservé")
    func audioToMixed() {
        var column = Column.empty(name: "C", kind: .audio)
        column.slots[0] = Self.sound()
        column.level = 0.55
        column.filter = 0.5
        let plan = ConversionPlan.column(column, to: .mixed)
        #expect(plan.isLossless)
        let converted = column.converted(to: .mixed)
        #expect(converted.kind == .mixed)
        #expect(converted.slots == column.slots)
        #expect(converted.level == 0.55)
        #expect(converted.filter == 0.5)
    }

    @Test("Lumière → Son et lumière : pads inchangés, le fader devient un volume (0,8), appairage du fader oublié")
    func lightToMixed() {
        var column = Column.empty(name: "C", kind: .light)
        column.slots[0] = Self.cue()
        column.level = 0.3
        column.isFaderPaired = true
        let plan = ConversionPlan.column(column, to: .mixed)
        #expect(plan.faderPairingForgotten)
        #expect(!plan.isLossless)  // l'appairage du fader est perdu : confirmation
        #expect(plan.deletedPads.isEmpty)
        let converted = column.converted(to: .mixed)
        #expect(converted.slots == column.slots)
        #expect(converted.level == 0.8)
        #expect(!converted.isFaderPaired)
    }

    @Test("Lumière → Son et lumière avec un fader non appairé : aucune perte")
    func lightToMixedUnpaired() {
        var column = Column.empty(name: "C", kind: .light)
        column.slots[0] = Self.cue()
        #expect(ConversionPlan.column(column, to: .mixed).isLossless)
    }

    @Test("Son et lumière → Son : pads lumière supprimés ; pads mixtes perdent leur cue appairée et deviennent des pads son")
    func mixedToAudio() throws {
        let column = Self.column(.mixed, level: 0.7)
        let plan = ConversionPlan.column(column, to: .audio)
        #expect(plan.deletedPads.map(\.title) == ["Plein feu"])
        #expect(plan.padsLosingLight.map(\.title) == ["Aube"])
        #expect(plan.padsLosingSound.isEmpty)
        #expect(!plan.isLossless)
        let converted = column.converted(to: .audio)
        #expect(converted.kind == .audio)
        #expect(converted.slots[0] == column.slots[0])  // le pad son est intact
        #expect(converted.slots[1] == nil)  // la cue seule disparaît
        let remaining = try #require(converted.slots[2])
        #expect(remaining.kind == .audio)
        #expect(remaining.audio == Self.clip)
        #expect(remaining.light == nil)
        #expect(remaining.id == column.slots[2]?.id)  // même pad, même identifiant
        #expect(converted.level == 0.7)
    }

    @Test("Son et lumière → Son : un pad « en attente de son » n'a rien à garder et disparaît")
    func mixedToAudioAwaiting() {
        var column = Column.empty(name: "C", kind: .mixed)
        column.slots[0] = Self.waiting()
        let plan = ConversionPlan.column(column, to: .audio)
        #expect(plan.deletedPads.map(\.title) == ["À venir"])
        #expect(column.converted(to: .audio).slots[0] == nil)
    }

    @Test("Son et lumière → Son : une cue vierge non appairée se retire sans confirmation")
    func mixedToAudioBlankCue() {
        var column = Column.empty(name: "C", kind: .mixed)
        column.slots[0] = Pad(title: "S", tint: .vert, audio: Self.clip, light: .blank)
        #expect(ConversionPlan.column(column, to: .audio).isLossless)
    }

    @Test("Son et lumière → Lumière : pads son supprimés ; pads mixtes perdent leur son ; filtre remis au neutre, niveau 1")
    func mixedToLight() throws {
        let column = Self.column(.mixed, level: 0.6, filter: -0.4)
        let plan = ConversionPlan.column(column, to: .light)
        #expect(plan.deletedPads.map(\.title) == ["Orage"])
        #expect(plan.padsLosingSound.map(\.title) == ["Aube"])
        #expect(plan.padsLosingLight.isEmpty)
        #expect(plan.filterReset)
        let converted = column.converted(to: .light)
        #expect(converted.kind == .light)
        #expect(converted.slots[0] == nil)
        #expect(converted.slots[1] == column.slots[1])
        let remaining = try #require(converted.slots[2])
        #expect(remaining.kind == .light)
        #expect(remaining.audio == nil)
        #expect(remaining.light == Self.pairedCue)  // la cue appairée est gardée
        #expect(remaining.title == "Aube")
        #expect(converted.filter == 0)
        #expect(converted.level == 1)
    }

    @Test("Son et lumière → Lumière : un pad « en attente de son » devient un simple pad lumière")
    func mixedToLightAwaiting() throws {
        var column = Column.empty(name: "C", kind: .mixed)
        column.slots[0] = Self.waiting()
        let plan = ConversionPlan.column(column, to: .light)
        #expect(plan.isLossless)
        let pad = try #require(column.converted(to: .light).slots[0])
        #expect(pad.kind == .light)
        #expect(!pad.awaitsSound)
    }

    @Test("Son → Lumière : tous les pads supprimés")
    func audioToLight() {
        var column = Column.empty(name: "C", kind: .audio)
        column.slots[0] = Self.sound("A")
        column.slots[1] = Self.sound("B")
        column.filter = 0.2
        let plan = ConversionPlan.column(column, to: .light)
        #expect(plan.deletedPads.map(\.title) == ["A", "B"])
        let converted = column.converted(to: .light)
        #expect(converted.slots.allSatisfy { $0 == nil })
        #expect(converted.level == 1)
        #expect(converted.filter == 0)
    }

    @Test("Lumière → Son : tous les pads supprimés ; niveau 0,8, appairage du fader oublié")
    func lightToAudio() {
        var column = Column.empty(name: "C", kind: .light)
        column.slots[0] = Self.cue("A")
        column.isFaderPaired = true
        let plan = ConversionPlan.column(column, to: .audio)
        #expect(plan.deletedPads.map(\.title) == ["A"])
        #expect(plan.faderPairingForgotten)
        let converted = column.converted(to: .audio)
        #expect(converted.slots.allSatisfy { $0 == nil })
        #expect(converted.level == 0.8)
        #expect(!converted.isFaderPaired)
    }

    @Test("Même type : rien ne change")
    func sameKind() {
        let column = Self.column(.mixed)
        #expect(ConversionPlan.column(column, to: .mixed).isLossless)
        #expect(column.converted(to: .mixed) == column)
    }

    @Test("Le nom, l'identifiant et les cases vides de la colonne sont gardés")
    func identityKept() {
        let column = Self.column(.mixed)
        let converted = column.converted(to: .audio)
        #expect(converted.id == column.id)
        #expect(converted.name == column.name)
        #expect(converted.slots.count == PadGrid.size)
    }

    // MARK: Pads (tableau 2)

    @Test("Pad : Son → Son et lumière ajoute une cue vierge non appairée")
    func padAudioToMixed() throws {
        let pad = Self.sound()
        let plan = ConversionPlan.pad(pad, to: .mixed)
        #expect(plan.isLossless)
        let converted = try #require(pad.converted(to: .mixed))
        #expect(converted.kind == .mixed)
        #expect(converted.audio == Self.clip)
        #expect(converted.light == .blank)
        #expect(converted.light?.isPaired == false)
        #expect(!converted.awaitsSound)
    }

    @Test("Pad : Lumière → Son et lumière attend son son")
    func padLightToMixed() throws {
        let pad = Self.cue()
        let converted = try #require(pad.converted(to: .mixed))
        #expect(converted.awaitsSound)
        #expect(converted.audio == nil)
        #expect(converted.light == Self.pairedCue)
        #expect(converted.kind == .mixed)
        #expect(ConversionPlan.pad(pad, to: .mixed).isLossless)
    }

    @Test("Pad : Son et lumière → Son retire la cue ; confirmation si elle était appairée")
    func padMixedToAudio() throws {
        let pad = Self.both()
        let plan = ConversionPlan.pad(pad, to: .audio)
        #expect(plan.padsLosingLight.map(\.title) == ["Aube"])
        let converted = try #require(pad.converted(to: .audio))
        #expect(converted.light == nil)
        #expect(converted.audio == Self.clip)
        var blank = pad
        blank.light = .blank
        #expect(ConversionPlan.pad(blank, to: .audio).isLossless)
    }

    @Test("Pad : Son et lumière → Lumière retire le son et ses réglages : confirmation")
    func padMixedToLight() throws {
        let pad = Self.both()
        let plan = ConversionPlan.pad(pad, to: .light)
        #expect(plan.padsLosingSound.map(\.title) == ["Aube"])
        let converted = try #require(pad.converted(to: .light))
        #expect(converted.audio == nil)
        #expect(converted.light == Self.pairedCue)
        #expect(converted.title == "Aube" && converted.tint == .rose)
    }

    @Test("Pad : Son → Lumière remplace le son par une cue vierge ; titre, sous-titre, teinte et intensité gardés")
    func padAudioToLight() throws {
        let pad = Self.sound()
        let plan = ConversionPlan.pad(pad, to: .light)
        #expect(plan.padsLosingSound.map(\.title) == ["Orage"])
        let converted = try #require(pad.converted(to: .light))
        #expect(converted.audio == nil)
        #expect(converted.light == .blank)
        #expect(converted.title == "Orage")
        #expect(converted.subtitle == "Ambiance")
        #expect(converted.tint == .azur)
        #expect(converted.ledIntensity == .half)
        #expect(converted.id == pad.id)
    }

    @Test("Pad : Lumière → Son n'a aucun son à garder : le pad disparaît (confirmation)")
    func padLightToAudio() {
        let pad = Self.cue()
        #expect(pad.converted(to: .audio) == nil)
        let plan = ConversionPlan.pad(pad, to: .audio)
        #expect(plan.deletedPads.map(\.title) == ["Plein feu"])
        #expect(!plan.isLossless)
    }

    @Test("Pad : « en attente de son » → Son disparaît ; → Lumière devient un pad lumière")
    func padAwaiting() throws {
        let pad = Self.waiting()
        #expect(pad.converted(to: .audio) == nil)
        let light = try #require(pad.converted(to: .light))
        #expect(light.kind == .light && !light.awaitsSound)
    }

    @Test("Pad : même type, aucun changement")
    func padSameKind() {
        for pad in [Self.sound(), Self.cue(), Self.both()] {
            #expect(pad.converted(to: pad.kind) == pad)
            #expect(ConversionPlan.pad(pad, to: pad.kind).isLossless)
        }
    }

    @Test("Un pad converti reste valide dans la colonne qui l'accepte")
    func convertedPadsValidate() throws {
        var show = Show.new()
        show.grids[0].columns[0] = Column.empty(name: "M", kind: .mixed)
        for kind in [PadKind.audio, .light, .mixed] {
            for pad in [Self.sound(), Self.cue(), Self.both(), Self.waiting()] {
                guard let converted = pad.converted(to: kind) else { continue }
                show.grids[0].columns[0].slots[0] = converted
                try show.validate()
            }
        }
    }
}
