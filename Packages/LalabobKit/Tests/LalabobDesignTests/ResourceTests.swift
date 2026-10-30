import AppKit
import Testing

@testable import LalabobDesign

@Suite("Ressources graphiques")
struct ResourceTests {
    @Test("Chaque icône déclarée existe dans le catalogue", arguments: Icon.allCases)
    func iconExists(icon: Icon) {
        let image = Bundle.module.image(forResource: icon.assetName)
        #expect(image != nil, "icône manquante : \(icon.assetName)")
        #expect(image?.isTemplate == true, "\(icon.assetName) doit être une image modèle (teintée par l'interface)")
    }

    @Test("La police Fredoka est disponible après enregistrement")
    func fredoka() {
        Fonts.register()
        Fonts.register()  // deux fois sans erreur
        #expect(NSFont(name: Fonts.logoFamily, size: 22) != nil)
    }

    @Test("Les licences sont livrées avec l'app")
    func licences() {
        #expect(Bundle.module.url(forResource: "Iconoir-LICENSE", withExtension: "txt") != nil)
        #expect(Bundle.module.url(forResource: "Fredoka-OFL", withExtension: "txt") != nil)
    }
}
