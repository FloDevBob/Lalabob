import Foundation

// Lumière autonome en DMX (J14, ADR 0012, plan `docs/plan-lumiere-dmx.md`) : le modèle. Valeurs pures et Codable ;
// l'envoi (`LalabobDMX`) et la console qui calcule les trames (`LalabobEngine`, étape 3) sont ailleurs.

// MARK: - Mode lumière

/// Qui pilote la lumière : LightKey (relais MIDI, ADR 0006) ou Lalabob lui-même (projecteurs en DMX).
public enum LightingMode: String, Codable, Sendable {
    case lightKey
    case dmx
}

/// Réglages lumière d'un spectacle. L'appareil est gardé même en mode LightKey : revenir d'un mode à l'autre ne perd rien.
/// Écrit dans le fichier seulement s'il diffère des valeurs par défaut (un spectacle sans DMX reste lisible par l'app
/// de la version 3).
public struct LightingSettings: Codable, Sendable, Equatable {
    public var mode: LightingMode
    public var rig: DMXRig

    public init(mode: LightingMode = .lightKey, rig: DMXRig = DMXRig()) {
        self.mode = mode
        self.rig = rig
    }
}

// MARK: - Couleurs

/// Une couleur de la roue : **teinte** (0 à moins de 360°) et **saturation** (0 = blanc, 1 = le plus intense).
/// Jamais un code RVB (esprit de la règle « une teinte est stockée ») : le profil de l'appareil la traduit
/// (`FixtureProfile.rgb(for:intensity:)`). L'intensité est un réglage à part.
public struct LightColor: Codable, Sendable, Equatable, Hashable {
    public private(set) var hue: Double
    public private(set) var saturation: Double

    public static let white = LightColor(hue: 0, saturation: 0)

    /// Teinte ramenée dans 0…360, saturation bornée à 0…1 ; une valeur non numérique devient 0.
    public init(hue: Double, saturation: Double) {
        var h = hue.isFinite ? hue.truncatingRemainder(dividingBy: 360) : 0
        if h < 0 { h += 360 }
        if h >= 360 { h = 0 }
        self.hue = h
        self.saturation = saturation.isNaN ? 0 : min(max(saturation, 0), 1)
    }

    /// Sans correction : pour qu'un fichier hors bornes se lise tel quel et soit refusé par `Show.validate()`.
    init(unchecked hue: Double, saturation: Double) {
        self.hue = hue
        self.saturation = saturation
    }

    private enum CodingKeys: String, CodingKey { case hue, saturation }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            unchecked: try container.decode(Double.self, forKey: .hue),
            saturation: try container.decode(Double.self, forKey: .saturation))
    }

    var isValid: Bool { hue.isFinite && (0..<360).contains(hue) && saturation.isFinite && (0...1).contains(saturation) }

    /// La couleur à pleine intensité (teinte sur la roue, saturation = part de blanc retirée).
    public var rgb: RGB {
        let c = saturation
        let sector = hue / 60
        let x = c * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double)
        switch Int(sector) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        let m = 1 - c
        func byte(_ v: Double) -> UInt8 { UInt8((min(max(v + m, 0), 1) * 255).rounded()) }
        return RGB(red: byte(r), green: byte(g), blue: byte(b))
    }
}

// MARK: - Profil d'appareil

/// Un canal d'un appareil DMX : son rôle et, pour une couleur, le projecteur (1, 2…) ; 0 pour un canal de toute la barre.
public struct FixtureChannel: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable {
        /// Programme : une valeur fixe (`directValue`) = pilotage DMX direct ; d'autres = programmes de la barre.
        case program
        /// Gradateur général.
        case dimmer
        case strobe
        case red, green, blue
    }

    public var role: Role
    public var head: Int

    public init(role: Role, head: Int = 0) {
        self.role = role
        self.head = head
    }
}

/// Ce que Lalabob sait d'un appareil DMX : **des données, pas du code** — un autre appareil s'ajoute sans recompiler.
/// Le profil intégré est celui de la barre de la troupe, relevé le 27/11/2026 (`docs/hardware/chauvet-4bar-ltbt.md`).
public struct FixtureProfile: Codable, Sendable, Equatable {
    /// Programmes automatiques de l'appareil : `count` numéros répartis de `first` à `last` (une valeur par numéro).
    public struct Programs: Codable, Sendable, Equatable {
        public var count: Int
        public var first: UInt8
        public var last: UInt8

        public init(count: Int, first: UInt8, last: UInt8) {
            self.count = count
            self.first = first
            self.last = last
        }
    }

    public var id: String
    public var name: String
    /// Les canaux dans l'ordre, depuis l'adresse de départ.
    public var channels: [FixtureChannel]
    /// Valeur du canal programme pour le pilotage DMX direct (à tenir : sinon la barre lance un programme).
    public var directValue: UInt8
    /// Strobo : valeur la plus lente et la plus rapide ; en dessous de la plus lente, pas de strobo.
    public var strobeSlowest: UInt8
    public var strobeFastest: UInt8
    /// Programmes automatiques ; `nil` = l'appareil n'en a pas.
    public var programs: Programs?
    /// Valeur du canal programme pour « réagit au son » ; `nil` = l'appareil n'en a pas.
    public var soundActiveValue: UInt8?
    /// Correction réglable à l'œil : valeur envoyée = (intensité)^gamma × couleur. 1 = aucune.
    public var colorGamma: Double

    public init(
        id: String, name: String, channels: [FixtureChannel], directValue: UInt8 = 0, strobeSlowest: UInt8 = 10,
        strobeFastest: UInt8 = 255, programs: Programs? = nil, soundActiveValue: UInt8? = nil, colorGamma: Double = 1
    ) {
        self.id = id
        self.name = name
        self.channels = channels
        self.directValue = directValue
        self.strobeSlowest = strobeSlowest
        self.strobeFastest = strobeFastest
        self.programs = programs
        self.soundActiveValue = soundActiveValue
        self.colorGamma = colorGamma
    }

    /// Chauvet DJ 4BAR LT BT, mode 15 canaux : programme, gradateur, strobo, puis rouge / vert / bleu × 4 projecteurs.
    /// ⚠︎ Les valeurs des 12 programmes (10 à 249, réparties à égalité) et « sur le son » (250) sont déduites du manuel
    /// (10–249 : programmes, 250–255 : son) ; à confirmer au banc d'essai DMX.
    public static let chauvet4BarLTBT = FixtureProfile(
        id: "chauvet-4bar-ltbt-15ch", name: "Chauvet DJ 4BAR LT BT (15 canaux)",
        channels: [FixtureChannel(role: .program), FixtureChannel(role: .dimmer), FixtureChannel(role: .strobe)]
            + (1...4).flatMap { head in
                [FixtureChannel.Role.red, .green, .blue].map { FixtureChannel(role: $0, head: head) }
            },
        directValue: 0, strobeSlowest: 10, strobeFastest: 255, programs: Programs(count: 12, first: 10, last: 249),
        soundActiveValue: 250, colorGamma: 1)

    public var channelCount: Int { channels.count }

    /// Nombre de projecteurs (le plus grand numéro de projecteur).
    public var headCount: Int { channels.map(\.head).max() ?? 0 }

    /// Position (depuis 0) du canal de ce rôle ; `head` nil = canal de toute la barre.
    public func channelOffset(_ role: FixtureChannel.Role, head: Int? = nil) -> Int? {
        channels.firstIndex { $0.role == role && $0.head == (head ?? 0) }
    }

    /// Valeur du canal strobo pour une vitesse de 0 à 1 : 0 = aucun, sinon de la plus lente à la plus rapide.
    public func strobeValue(speed: Double) -> UInt8 {
        guard speed > 0 else { return 0 }
        let s = min(speed, 1)
        return UInt8((Double(strobeSlowest) + (Double(strobeFastest) - Double(strobeSlowest)) * s).rounded())
    }

    /// Valeur du canal programme pour le programme `number` (1…`count`) ; `nil` si l'appareil n'en a pas ou hors bornes.
    public func programValue(number: Int) -> UInt8? {
        guard let programs, programs.count > 0, (1...programs.count).contains(number) else { return nil }
        if programs.count == 1 { return programs.first }
        let span = Double(programs.last) - Double(programs.first)
        return UInt8((Double(programs.first) + Double(number - 1) * span / Double(programs.count - 1)).rounded())
    }

    /// Les trois valeurs rouge / vert / bleu d'une couleur à une intensité (0 à 1), correction comprise.
    public func rgb(for color: LightColor, intensity: Double) -> RGB {
        let i = intensity.isNaN ? 0 : min(max(intensity, 0), 1)
        let factor = pow(i, colorGamma)
        let base = color.rgb
        func scaled(_ v: UInt8) -> UInt8 { UInt8((Double(v) * factor).rounded()) }
        return RGB(red: scaled(base.red), green: scaled(base.green), blue: scaled(base.blue))
    }
}

// MARK: - Appareil du spectacle

/// L'appareil DMX d'un spectacle : profil, adresse de départ (celle affichée par la barre) et réglages de jeu.
public struct DMXRig: Codable, Sendable, Equatable {
    public enum QuitBehavior: String, Codable, Sendable {
        /// Éteindre en fondu avant de fermer (le signal s'arrête de toute façon : la barre garderait sa couleur).
        case fadeToBlack
        case leaveLight
    }

    public static let maximumFavoriteColors = 16
    public static let blackoutFadeRange = 0.0...10.0

    public var profile: FixtureProfile
    /// Adresse de départ réglée sur la barre (MENU → 15Ch → d …).
    public var address: Int
    /// Durée du Noir, en secondes.
    public var blackoutFade: Double
    public var onQuit: QuitBehavior
    /// Couleurs favorites du spectacle (pastilles sous la roue).
    public var favoriteColors: [LightColor]

    /// 1…498 pour 15 canaux : les canaux de l'appareil doivent tenir dans les 512.
    public static func addressRange(for profile: FixtureProfile) -> ClosedRange<Int> {
        1...max(1, min(512, 513 - profile.channelCount))
    }

    public init(
        profile: FixtureProfile = .chauvet4BarLTBT, address: Int = 1, blackoutFade: Double = 1.5,
        onQuit: QuitBehavior = .fadeToBlack, favoriteColors: [LightColor] = []
    ) {
        let range = Self.addressRange(for: profile)
        self.profile = profile
        self.address = min(max(address, range.lowerBound), range.upperBound)
        self.blackoutFade = blackoutFade
        self.onQuit = onQuit
        self.favoriteColors = favoriteColors
    }
}

// MARK: - États lumineux

/// Un projecteur dans un état « couleurs ».
public struct HeadLook: Codable, Sendable, Equatable {
    public var isOn: Bool
    public var color: LightColor
    /// 0 à 1.
    public var intensity: Double

    public init(isOn: Bool, color: LightColor, intensity: Double) {
        self.isOn = isOn
        self.color = color
        self.intensity = intensity
    }
}

/// État « couleurs » : une couleur et une intensité par projecteur.
public struct ColorsLook: Codable, Sendable, Equatable {
    /// Un par projecteur de l'appareil, dans l'ordre.
    public var heads: [HeadLook]
    /// Réglé « Ensemble » (une couleur et une intensité pour tous) plutôt que « Chacun » : option d'édition, mémorisée avec le pad.
    public var linked: Bool
    /// Vitesse du strobo (0 à 1) ; `nil` = pas de strobo (le défaut : jamais déclenché par erreur).
    public var strobe: Double?

    public init(heads: [HeadLook], linked: Bool, strobe: Double?) {
        self.heads = heads
        self.linked = linked
        self.strobe = strobe
    }
}

/// État « alternance » : deux couleurs qui s'échangent (A sur les projecteurs impairs, B sur les pairs), au tempo du son.
public struct AlternateLook: Codable, Sendable, Equatable {
    public enum Interval: String, Codable, Sendable {
        case beat, twoBeats, bar
    }

    public var a: LightColor
    public var b: LightColor
    public var every: Interval
    /// Durée du fondu à chaque bascule, en secondes (0 = net).
    public var switchFade: Double
    /// Tempo utilisé quand aucun son ne donne le sien.
    public var fallbackBPM: Double

    public init(a: LightColor, b: LightColor, every: Interval, switchFade: Double, fallbackBPM: Double) {
        self.a = a
        self.b = b
        self.every = every
        self.switchFade = switchFade
        self.fallbackBPM = fallbackBPM
    }
}

/// Un état lumineux : ce que fait la barre quand un pad lumière est joué (DMX).
public struct LightLook: Codable, Sendable, Equatable {
    public enum Content: Codable, Sendable, Equatable {
        case colors(ColorsLook)
        case alternate(AlternateLook)
        /// Un des programmes automatiques de l'appareil (numéro à partir de 1) et sa vitesse (0 à 1).
        case fixtureProgram(number: Int, speed: Double)
        /// L'appareil réagit au son de la salle (micro) ; sensibilité de 0 à 1.
        case soundActive(sensitivity: Double)

        private enum Kind: String, Codable { case colors, alternate, fixtureProgram, soundActive }
        private enum CodingKeys: String, CodingKey { case type, colors, alternate, number, speed, sensitivity }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(Kind.self, forKey: .type) {
            case .colors: self = .colors(try c.decode(ColorsLook.self, forKey: .colors))
            case .alternate: self = .alternate(try c.decode(AlternateLook.self, forKey: .alternate))
            case .fixtureProgram:
                self = .fixtureProgram(
                    number: try c.decode(Int.self, forKey: .number), speed: try c.decode(Double.self, forKey: .speed))
            case .soundActive: self = .soundActive(sensitivity: try c.decode(Double.self, forKey: .sensitivity))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .colors(let look):
                try c.encode(Kind.colors, forKey: .type)
                try c.encode(look, forKey: .colors)
            case .alternate(let look):
                try c.encode(Kind.alternate, forKey: .type)
                try c.encode(look, forKey: .alternate)
            case .fixtureProgram(let number, let speed):
                try c.encode(Kind.fixtureProgram, forKey: .type)
                try c.encode(number, forKey: .number)
                try c.encode(speed, forKey: .speed)
            case .soundActive(let sensitivity):
                try c.encode(Kind.soundActive, forKey: .type)
                try c.encode(sensitivity, forKey: .sensitivity)
            }
        }
    }

    /// Fondu d'entrée par défaut, en secondes.
    public static let defaultFadeIn = 0.5
    public static let fadeInRange = 0.0...30.0

    /// Fondu d'entrée depuis la lumière en cours, en secondes.
    public var fadeIn: Double
    public var content: Content

    public init(fadeIn: Double = LightLook.defaultFadeIn, content: Content) {
        self.fadeIn = fadeIn
        self.content = content
    }

    /// Une couleur et une intensité pour tous les projecteurs (« Ensemble »), tous allumés, sans strobo.
    public static func uniform(color: LightColor, intensity: Double, headCount: Int) -> LightLook {
        let head = HeadLook(isOn: true, color: color, intensity: intensity)
        return LightLook(
            content: .colors(ColorsLook(heads: Array(repeating: head, count: max(headCount, 1)), linked: true, strobe: nil)))
    }
}

// MARK: - Validation (tout ce qui vient d'un fichier)

private func isFraction(_ value: Double) -> Bool { value.isFinite && (0...1).contains(value) }

extension FixtureProfile {
    func validate() throws(ShowValidationError) {
        guard (1...DMXFrameLimits.channels).contains(channels.count) else { throw .valueOutOfRange("canaux de l'appareil") }
        guard id.count <= 200, name.count <= 200 else { throw .valueOutOfRange("nom de l'appareil") }
        var seen: Set<String> = []
        for channel in channels {
            guard (0...DMXFrameLimits.heads).contains(channel.head) else { throw .valueOutOfRange("projecteur") }
            switch channel.role {
            case .program, .dimmer, .strobe: guard channel.head == 0 else { throw .valueOutOfRange("canal de l'appareil") }
            case .red, .green, .blue: guard channel.head >= 1 else { throw .valueOutOfRange("canal de couleur") }
            }
            guard seen.insert("\(channel.role.rawValue)-\(channel.head)").inserted else { throw .valueOutOfRange("canal en double") }
        }
        guard strobeSlowest >= 1, strobeSlowest <= strobeFastest else { throw .valueOutOfRange("strobo de l'appareil") }
        if let programs {
            guard (1...64).contains(programs.count), programs.first <= programs.last else {
                throw .valueOutOfRange("programmes de l'appareil")
            }
        }
        guard colorGamma.isFinite, (0.2...5).contains(colorGamma) else { throw .valueOutOfRange("correction des couleurs") }
    }
}

extension DMXRig {
    func validate() throws(ShowValidationError) {
        try profile.validate()
        guard Self.addressRange(for: profile).contains(address) else { throw .valueOutOfRange("adresse DMX") }
        guard blackoutFade.isFinite, Self.blackoutFadeRange.contains(blackoutFade) else {
            throw .valueOutOfRange("fondu du noir")
        }
        guard favoriteColors.count <= Self.maximumFavoriteColors, favoriteColors.allSatisfy(\.isValid) else {
            throw .valueOutOfRange("couleurs favorites")
        }
    }
}

extension LightLook {
    /// Vérifie l'état pour cet appareil (nombre de projecteurs, programmes disponibles).
    func validate(for profile: FixtureProfile) throws(ShowValidationError) {
        guard fadeIn.isFinite, Self.fadeInRange.contains(fadeIn) else { throw .valueOutOfRange("fondu d'entrée") }
        switch content {
        case .colors(let look):
            guard look.heads.count == profile.headCount, !look.heads.isEmpty else { throw .valueOutOfRange("projecteurs de l'état") }
            for head in look.heads {
                guard isFraction(head.intensity), head.color.isValid else { throw .valueOutOfRange("projecteur de l'état") }
            }
            if let strobe = look.strobe { guard isFraction(strobe) else { throw .valueOutOfRange("strobo") } }
        case .alternate(let look):
            guard look.a.isValid, look.b.isValid else { throw .valueOutOfRange("couleur de l'alternance") }
            guard look.switchFade.isFinite, (0...0.5).contains(look.switchFade) else { throw .valueOutOfRange("fondu de bascule") }
            guard look.fallbackBPM.isFinite, (40...240).contains(look.fallbackBPM) else { throw .valueOutOfRange("tempo") }
        case .fixtureProgram(let number, let speed):
            guard let programs = profile.programs, (1...programs.count).contains(number) else {
                throw .valueOutOfRange("programme de l'appareil")
            }
            guard isFraction(speed) else { throw .valueOutOfRange("vitesse du programme") }
        case .soundActive(let sensitivity):
            guard profile.soundActiveValue != nil, isFraction(sensitivity) else { throw .valueOutOfRange("sensibilité au son") }
        }
    }
}

/// Bornes du DMX.
enum DMXFrameLimits {
    static let channels = 512
    /// Plus de projecteurs qu'une barre n'en a : au-delà, un fichier est suspect.
    static let heads = 16
}
