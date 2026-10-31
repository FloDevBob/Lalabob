import CoreGraphics
import Testing

@testable import LalabobDesign

/// Densité de la grille : quand la fenêtre est trop basse, les pads et la piste du fader rétrécissent (jusqu'à un
/// minimum lisible) pour que la grille, les cartes de volume et la barre du bas restent visibles sans défiler.
@Suite("Densité de la grille")
struct GridDensityTests {
    /// Hauteur totale occupée par la grille pour une densité donnée.
    private func total(_ density: GridDensity) -> CGFloat {
        8 * density.padHeight + density.faderTrackHeight + GridDensity.fixedHeight
    }

    @Test func aTallWindowKeepsTheRegularSizes() {
        let density = GridDensity.fitting(availableHeight: 1000)
        #expect(density == .regular)
        #expect(density.padHeight == Metrics.padHeight)
        #expect(density.faderTrackHeight == 120)
    }

    @Test func theRegularSizesJustFitTheirOwnHeight() {
        #expect(GridDensity.fitting(availableHeight: total(.regular)) == .regular)
    }

    @Test(arguments: [700, 650, 600, 560, 540] as [CGFloat])
    func aLowerWindowShrinksTheGridToFitExactly(_ available: CGFloat) {
        let density = GridDensity.fitting(availableHeight: available)
        #expect(density.padHeight < Metrics.padHeight)
        #expect(density.padHeight >= GridDensity.minimumPadHeight)
        #expect(density.faderTrackHeight >= GridDensity.minimumFaderTrackHeight)
        #expect(total(density) <= available + 0.5)
    }

    @Test func theGridNeverShrinksBelowTheReadableMinimum() {
        let density = GridDensity.fitting(availableHeight: 200)
        #expect(density.padHeight == GridDensity.minimumPadHeight)
        #expect(density.faderTrackHeight == GridDensity.minimumFaderTrackHeight)
    }

    @Test func shrinkingIsMonotonic() {
        var previous = GridDensity.fitting(availableHeight: 1000)
        for available in stride(from: 1000, through: 300, by: -20) {
            let density = GridDensity.fitting(availableHeight: CGFloat(available))
            #expect(density.padHeight <= previous.padHeight)
            #expect(density.faderTrackHeight <= previous.faderTrackHeight)
            previous = density
        }
    }

    @Test func invalidHeightsGiveTheRegularSizes() {
        #expect(GridDensity.fitting(availableHeight: .nan) == .regular)
        #expect(GridDensity.fitting(availableHeight: .infinity) == .regular)
    }

    @Test func aFullScreenLaptopShowsEverything() {
        // Écran de 900 pt de haut en plein écran : en-tête (57) et barre du bas (197) réservés.
        let available: CGFloat = 900 - 57 - 197
        let density = GridDensity.fitting(availableHeight: available)
        #expect(total(density) <= available + 0.5)
        #expect(density.padHeight >= 44)  // reste confortable
    }
}
