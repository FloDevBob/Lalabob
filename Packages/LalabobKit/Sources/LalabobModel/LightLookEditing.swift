import Foundation

// Édition d'un état lumineux (J14, étape 4c) : changer de type, passer de « Chacun » à « Ensemble ». Valeurs pures : le panneau
// du bas les appelle, `ShowController.setLook` les enregistre (⌘Z).

extension LightLook.Content {
    /// Le type d'un état, tel que le panneau du bas le propose : Couleurs · Alternance · Programme · Sur le son.
    public enum Style: String, CaseIterable, Sendable {
        case colors, alternate, fixtureProgram, soundActive

        public var title: String {
            switch self {
            case .colors: "Couleurs"
            case .alternate: "Alternance"
            case .fixtureProgram: "Programme"
            case .soundActive: "Sur le son"
            }
        }
    }

    public var style: Style {
        switch self {
        case .colors: .colors
        case .alternate: .alternate
        case .fixtureProgram: .fixtureProgram
        case .soundActive: .soundActive
        }
    }
}

extension FixtureProfile {
    /// Les types d'état que cet appareil sait jouer (une barre sans programmes n'a pas « Programme »).
    public var supportedLookStyles: [LightLook.Content.Style] {
        var kinds: [LightLook.Content.Style] = [.colors, .alternate]
        if programs != nil { kinds.append(.fixtureProgram) }
        if soundActiveValue != nil { kinds.append(.soundActive) }
        return kinds
    }
}

extension LightLook {
    /// Cet état est jouable sur cet appareil (nombre de projecteurs, programmes, bornes). Sert à refuser une édition invalide.
    public func isValid(for profile: FixtureProfile) -> Bool {
        (try? validate(for: profile)) != nil
    }

    /// Le même état changé de type, en gardant le fondu d'entrée et ce qui se garde (les couleurs d'un état « couleurs »
    /// deviennent celles de l'alternance, et inversement). `nil` si l'appareil ne sait pas jouer ce type.
    public func converted(to style: Content.Style, profile: FixtureProfile) -> LightLook? {
        guard profile.supportedLookStyles.contains(style) else { return nil }
        if content.style == style { return self }
        let heads = max(profile.headCount, 1)
        let new: Content
        switch (content, style) {
        case (.colors(let look), .alternate):
            let lit = look.heads.filter { $0.isOn && $0.intensity > 0 }
            let a = lit.first?.color ?? look.heads.first?.color ?? .white
            var b = lit.dropFirst().first(where: { $0.color != a })?.color ?? a
            if b == a { b = LightColor(hue: a.hue + 180, saturation: 1) }  // un seul ton : son opposé sur la roue
            new = .alternate(AlternateLook(a: a, b: b, every: .beat, switchFade: 0.1, fallbackBPM: 120))
        case (.alternate(let look), .colors):
            let hds = (0..<heads).map { HeadLook(isOn: true, color: $0 % 2 == 0 ? look.a : look.b, intensity: 1) }
            new = .colors(ColorsLook(heads: hds, linked: false, strobe: nil))
        case (_, .colors):
            return LightLook(fadeIn: fadeIn, content: LightLook.uniform(color: .white, intensity: 1, headCount: heads).content)
        case (_, .alternate):
            guard let colors = converted(to: .colors, profile: profile) else { return nil }
            return colors.converted(to: .alternate, profile: profile).map { LightLook(fadeIn: fadeIn, content: $0.content) }
        case (_, .fixtureProgram): new = .fixtureProgram(number: 1, speed: 0.5)
        case (_, .soundActive): new = .soundActive(sensitivity: 0.5)
        }
        return LightLook(fadeIn: fadeIn, content: new)
    }
}

extension ColorsLook {
    /// Passe de « Chacun » à « Ensemble » (ou l'inverse). En « Ensemble », les quatre projecteurs prennent la couleur et
    /// l'intensité du projecteur `source` (0 = le premier) ; ceux qui étaient allumés ou éteints le restent. Revenir à
    /// « Chacun » ne change aucune couleur.
    public func settingLinked(_ linked: Bool, source: Int = 0) -> ColorsLook {
        var result = self
        result.linked = linked
        guard linked, heads.indices.contains(source) else { return result }
        let reference = heads[source]
        for index in result.heads.indices {
            result.heads[index].color = reference.color
            result.heads[index].intensity = reference.intensity
        }
        return result
    }
}
