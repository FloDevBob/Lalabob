import Foundation
import Testing

@testable import LalabobModel

@Suite("Filtre de colonne : spectacle")
struct ColumnFilterTests {
    @Test("Une colonne neuve est au neutre")
    func defaultsToNeutral() {
        let grid = PadGrid.empty(name: "G")
        #expect(grid.columns.allSatisfy { $0.filter == 0 })
    }

    @Test("Le réglage du filtre est enregistré puis relu")
    func roundTrip() throws {
        var show = Show.new()
        show.grids[0].columns[2].filter = -0.4
        let decoded = try JSONDecoder().decode(Show.self, from: JSONEncoder().encode(show))
        #expect(decoded.grids[0].columns[2].filter == -0.4)
        try decoded.validate()
    }

    @Test("Un ancien fichier, sans réglage de filtre, s'ouvre au neutre")
    func oldFilesOpenNeutral() throws {
        var show = Show.new()
        show.grids[0].columns[0].filter = 0.7
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(show)) as? [String: Any])
        var grids = try #require(json["grids"] as? [[String: Any]])
        var columns = try #require(grids[0]["columns"] as? [[String: Any]])
        for i in columns.indices { columns[i].removeValue(forKey: "filter") }
        grids[0]["columns"] = columns
        json["grids"] = grids
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Show.self, from: data)
        #expect(decoded.grids[0].columns.allSatisfy { $0.filter == 0 })
        try decoded.validate()
    }

    @Test("Un réglage hors bornes est refusé à l'ouverture", arguments: [1.5, -1.01, Double.nan, Double.infinity])
    func outOfRangeIsRejected(value: Double) {
        var show = Show.new()
        show.grids[0].columns[1].filter = value
        #expect(throws: ShowValidationError.valueOutOfRange("filtre de colonne")) { try show.validate() }
    }

    @Test("Les bornes elles-mêmes sont acceptées", arguments: [-1.0, 0, 1])
    func boundsAreAccepted(value: Double) throws {
        var show = Show.new()
        show.grids[0].columns[1].filter = value
        try show.validate()
    }
}
