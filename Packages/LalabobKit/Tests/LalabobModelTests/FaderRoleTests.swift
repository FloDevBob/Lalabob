import Foundation
import Testing

@testable import LalabobModel

@Suite("Rôle du fader d'une colonne lumière")
struct FaderRoleTests {
    func show(role: DMXFaderRole?) -> Show {
        var grid = PadGrid.empty(name: "G")
        grid.columns[7].faderRole = role
        return Show(name: "S", grids: [grid])
    }

    @Test("Sans rôle choisi, le fichier reste en version 2 et n'écrit pas la clé")
    func defaultNotWritten() throws {
        let data = try ShowPackage.encode(show(role: nil))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("faderRole"))
        #expect(try ShowPackage.decode(data).formatVersion == 2)
    }

    @Test("Un rôle choisi : version 4, relu à l'identique")
    func roleRoundTrip() throws {
        let original = show(role: DMXFaderRole.strobeSpeed)
        #expect(original.requiredFormatVersion == 4)
        let decoded = try ShowPackage.decode(ShowPackage.encode(original))
        #expect(decoded.grids[0].columns[7].faderRole == .strobeSpeed)
        #expect(decoded.formatVersion == 4)
    }

    @Test("« Aucun » est un choix, pas l'absence de choix")
    func noneIsExplicit() throws {
        let decoded = try ShowPackage.decode(ShowPackage.encode(show(role: DMXFaderRole.none)))
        #expect(decoded.grids[0].columns[7].faderRole == DMXFaderRole.none)
    }

    @Test("Une colonne qui quitte la lumière oublie son rôle")
    func conversionForgetsRole() {
        var column = Column.empty(name: "L", kind: .light)
        column.faderRole = .general
        #expect(column.converted(to: .audio).faderRole == nil)
    }
}
