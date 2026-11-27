import Foundation

// Libellé automatique d'un pad lumière (J14) : quand on règle ses couleurs en mode Projecteurs, le pad reçoit un titre d'ambiance
// que tout le monde comprend (« Lumière du jour », « Soir »…) et, en sous-titre, le nom simple de la couleur (« Blanc », « Orange »).
// Valeurs pures ; `ShowController.setLook` ne s'en sert que si le titre ou le sous-titre sont encore ceux d'origine.

/// Une couleur de la roue, nommée pour des non-spécialistes : un nom simple et une ambiance.
public struct LightColorName: Equatable, Sendable {
    /// Nom simple : « Blanc », « Blanc chaud », « Orange »…
    public let plain: String
    /// Nom d'ambiance : « Lumière du jour », « Soir »…
    public let mood: String
}

extension LightColor {
    /// Les blancs légèrement teintés comptent comme blancs jusqu'à cette saturation.
    private static let paleLimit = 0.4

    /// Le nom de cette couleur. Un blanc pur est « Blanc » ; un blanc teinté vers l'orange est « chaud », vers le bleu « froid ».
    public var name: LightColorName {
        if saturation < 0.12 { return LightColorName(plain: "Blanc", mood: "Lumière du jour") }
        if saturation < Self.paleLimit {
            if hue <= 70 || hue >= 330 { return LightColorName(plain: "Blanc chaud", mood: "Lumière douce") }
            if (180...270).contains(hue) { return LightColorName(plain: "Blanc froid", mood: "Lumière froide") }
        }
        switch hue {
        case 345..<360, 0..<15: return LightColorName(plain: "Rouge", mood: "Danger")
        case 15..<45: return LightColorName(plain: "Orange", mood: "Soir")
        case 45..<70: return LightColorName(plain: "Jaune", mood: "Soleil")
        case 70..<160: return LightColorName(plain: "Vert", mood: "Forêt")
        case 160..<200: return LightColorName(plain: "Turquoise", mood: "Mer")
        case 200..<255: return LightColorName(plain: "Bleu", mood: "Nuit")
        case 255..<290: return LightColorName(plain: "Violet", mood: "Mystère")
        default: return LightColorName(plain: "Rose", mood: "Romantique")
        }
    }
}

/// Titre et sous-titre par défaut d'un pad lumière.
public struct LightLabel: Equatable, Sendable {
    public let title: String
    public let subtitle: String
}

extension LightLook {
    /// Le titre d'origine d'une lumière neuve.
    public static let blankTitle = "Nouvelle lumière"

    /// Le libellé que mérite cet état : une ambiance et le nom de la couleur ; « Plusieurs couleurs » quand les projecteurs allumés
    /// n'ont pas la même ; « Noir » quand tout est éteint ; un nom pour l'alternance, le programme de la barre et « sur le son ».
    public var autoLabel: LightLabel {
        switch content {
        case .colors(let look):
            let lit = look.heads.filter { $0.isOn && $0.intensity > 0 }
            guard let first = lit.first else { return LightLabel(title: "Noir", subtitle: "Tout éteint") }
            let names = lit.reduce(into: [LightColorName]()) { names, head in
                if !names.contains(head.color.name) { names.append(head.color.name) }
            }
            if names.count > 1 {
                let listed = names.prefix(2).map(\.plain).joined(separator: " et ")
                return LightLabel(title: "Plusieurs couleurs", subtitle: names.count > 2 ? listed + "…" : listed)
            }
            let name = first.color.name
            return LightLabel(title: name.mood, subtitle: name.plain)
        case .alternate(let look):
            let a = look.a.name.plain, b = look.b.name.plain
            return LightLabel(title: "Alternance", subtitle: a == b ? a : "\(a) et \(b)")
        case .fixtureProgram(let number, _):
            return LightLabel(title: "Programme \(number)", subtitle: "Programme de la barre")
        case .soundActive:
            return LightLabel(title: "Au rythme du son", subtitle: "Micro de la barre")
        }
    }
}
