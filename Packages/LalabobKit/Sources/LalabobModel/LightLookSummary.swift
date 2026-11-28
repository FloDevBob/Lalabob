import Foundation

/// Ce qu'on montre d'un état lumineux sur son pad (J14, étape 4b) : un repère de quatre points (un par projecteur), des
/// drapeaux (⇄ alternance, ϟ strobo, « P3 » programme, « MIC » sur le son) et un sous-titre par défaut. Valeurs pures :
/// l'app n'a plus qu'à les dessiner.
public struct LightLookSummary: Equatable, Sendable {
    /// Un projecteur dans le repère : éteint, ou allumé à sa couleur et son intensité (0 à 1).
    public struct Dot: Equatable, Sendable {
        public var isOn: Bool
        public var color: LightColor
        public var intensity: Double
    }

    public enum Kind: Equatable, Sendable {
        case colors, alternate, program(number: Int), sound
    }

    public var kind: Kind
    /// Un point par projecteur ; vide pour un programme de la barre ou « sur le son » (la barre choisit ses couleurs).
    public var dots: [Dot]
    public var hasStrobe: Bool
    /// Sous-titre à montrer quand le pad n'en a pas : « Ensemble · 2 et 3 », « ⇄ 124 BPM · son en cours »…
    public var subtitle: String
}

extension LightLook {
    /// Le résumé de cet état (voir `LightLookSummary`).
    public var summary: LightLookSummary {
        switch content {
        case .colors(let look):
            let dots = look.heads.map { LightLookSummary.Dot(isOn: $0.isOn && $0.intensity > 0, color: $0.color, intensity: $0.intensity) }
            let lit = dots.indices.filter { dots[$0].isOn }.map { $0 + 1 }
            let strobe = look.strobe.map { $0 > 0 } ?? false
            var text = lit.isEmpty ? "Éteint" : "\(look.linked ? "Ensemble" : "Chacun") · \(Self.headList(lit, of: dots.count))"
            if strobe { text += " · Strobo" }
            return LightLookSummary(kind: .colors, dots: dots, hasStrobe: strobe, subtitle: text)
        case .alternate(let look):
            // A sur les projecteurs impairs (1 et 3), B sur les pairs (2 et 4).
            let dots = (0..<4).map {
                LightLookSummary.Dot(isOn: true, color: $0 % 2 == 0 ? look.a : look.b, intensity: 1)
            }
            let text = "⇄ \(Int(look.fallbackBPM.rounded())) BPM · son en cours"
            return LightLookSummary(kind: .alternate, dots: dots, hasStrobe: false, subtitle: text)
        case .fixtureProgram(let number, let speed):
            let text = "Programme \(number) · \(Int((speed * 100).rounded())) %"
            return LightLookSummary(kind: .program(number: number), dots: [], hasStrobe: false, subtitle: text)
        case .soundActive(let sensitivity):
            let text = "Sur le son · \(Int((sensitivity * 100).rounded())) %"
            return LightLookSummary(kind: .sound, dots: [], hasStrobe: false, subtitle: text)
        }
    }

    /// « les 4 », « 2 et 3 », « 1, 2 et 4 », « 3 ».
    private static func headList(_ numbers: [Int], of count: Int) -> String {
        if numbers.count == count, count > 1 { return "les \(count)" }
        guard numbers.count > 1, let last = numbers.last else { return numbers.first.map(String.init) ?? "" }
        return numbers.dropLast().map(String.init).joined(separator: ", ") + " et \(last)"
    }
}
