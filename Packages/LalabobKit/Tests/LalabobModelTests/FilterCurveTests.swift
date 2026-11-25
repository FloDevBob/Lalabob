import Foundation
import Testing

@testable import LalabobModel

@Suite("Filtre de colonne : courbe")
struct FilterCurveTests {
    @Test("Le centre est exactement neutre")
    func centerIsNeutral() {
        #expect(FilterCurve.mode(for: 0) == .neutral)
        #expect(FilterCurve.mode(for: -0.0) == .neutral)
        #expect(FilterCurve.label(for: 0) == "Neutre")
    }

    @Test("À gauche, un passe-bas ; à droite, un passe-haut")
    func sides() {
        guard case .lowPass = FilterCurve.mode(for: -0.5) else { Issue.record("passe-bas attendu"); return }
        guard case .highPass = FilterCurve.mode(for: 0.5) else { Issue.record("passe-haut attendu"); return }
    }

    @Test("Les fréquences extrêmes respectent les bornes")
    func bounds() {
        #expect(FilterCurve.mode(for: -1) == .lowPass(cutoff: FilterCurve.lowPassMinimum))
        #expect(FilterCurve.mode(for: 1) == .highPass(cutoff: FilterCurve.highPassMaximum))
        #expect(abs(FilterCurve.cutoff(for: -0.0001) - FilterCurve.lowPassMaximum) < 20)
        #expect(abs(FilterCurve.cutoff(for: 0.0001) - FilterCurve.highPassMinimum) < 0.1)
        for step in -100...100 {
            let x = Double(step) / 100
            let f = FilterCurve.cutoff(for: x)
            #expect(f >= FilterCurve.highPassMinimum && f <= FilterCurve.lowPassMaximum)
        }
    }

    @Test("Plus on tourne, plus la coupure s'éloigne du neutre (courbe monotone)")
    func monotonic() {
        var previous = Double.infinity
        for step in 1...100 {  // vers la gauche : la coupure du passe-bas descend
            let f = FilterCurve.cutoff(for: -Double(step) / 100)
            #expect(f < previous)
            previous = f
        }
        previous = 0
        for step in 1...100 {  // vers la droite : la coupure du passe-haut monte
            let f = FilterCurve.cutoff(for: Double(step) / 100)
            #expect(f > previous)
            previous = f
        }
    }

    @Test("Échelle logarithmique : le milieu de la course est la moyenne géométrique des bornes")
    func logarithmic() {
        let lowMid = (FilterCurve.lowPassMaximum * FilterCurve.lowPassMinimum).squareRoot()
        let highMid = (FilterCurve.highPassMinimum * FilterCurve.highPassMaximum).squareRoot()
        #expect(abs(FilterCurve.cutoff(for: -0.5) - lowMid) < 1)
        #expect(abs(FilterCurve.cutoff(for: 0.5) - highMid) < 1)
    }

    @Test("Valeurs hors bornes ou non numériques ramenées dans la plage")
    func clamping() {
        #expect(FilterCurve.clamped(3) == 1)
        #expect(FilterCurve.clamped(-7) == -1)
        #expect(FilterCurve.clamped(.nan) == 0)
        #expect(FilterCurve.clamped(.infinity) == 1)
        #expect(FilterCurve.mode(for: .nan) == .neutral)
    }

    @Test("Près du centre, la position est aimantée au neutre")
    func snapping() {
        #expect(FilterCurve.snapped(0.03) == 0)
        #expect(FilterCurve.snapped(-0.03) == 0)
        #expect(FilterCurve.snapped(0.2) == 0.2)
        #expect(FilterCurve.snapped(4) == 1)
    }

    @Test("Étiquettes de l'interface", arguments: [
        (800.0, "800 Hz"), (84.0, "84 Hz"), (1000.0, "1 kHz"), (2049.0, "2 kHz"), (2150.0, "2,2 kHz"),
        (16_600.0, "17 kHz"), (20_000.0, "20 kHz"), (199.6, "200 Hz"),
    ])
    func frequencyText(frequency: Double, expected: String) {
        #expect(FilterCurve.formatFrequency(frequency) == expected)
    }

    @Test("L'étiquette dit le côté et la coupure")
    func labels() {
        #expect(FilterCurve.label(for: -1) == "Bas 200 Hz")
        #expect(FilterCurve.label(for: 1) == "Haut 5 kHz")
        #expect(FilterCurve.label(for: -0.5).hasPrefix("Bas "))
        #expect(FilterCurve.label(for: 0.5).hasPrefix("Haut "))
    }
}
