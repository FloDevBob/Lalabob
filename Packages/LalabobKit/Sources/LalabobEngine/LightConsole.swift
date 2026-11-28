import Foundation
import LalabobDMX
import LalabobModel

/// La console lumière DMX (J14, étape 3, ADR 0012) : l'état de la barre, et la trame qui en découle à un instant donné.
///
/// **Pure** : une valeur, sans horloge ni E/S. Le moteur la modifie (appui, Noir, projecteurs, faders) en datant chaque
/// geste ; la sortie DMX la recopie et appelle `frame(at:)` à chaque rafraîchissement, sur son propre fil — un fondu avance
/// donc même si l'interface rame, et rien ne touche jamais au son.
///
/// Fondus : chaque changement part de **la lumière en cours** (fondu interrompu compris), mélangée linéairement vers la
/// nouvelle. Les canaux qui ne se mélangent pas (programme de la barre, strobo) changent au début du fondu, sauf vers le
/// noir où ils tiennent jusqu'à la fin (un programme s'éteint alors par le gradateur).
public struct LightConsole: DMXFrameSource, Equatable {
    /// Durée du fondu d'un projecteur allumé ou éteint à la main (mini-barre), en secondes.
    public static let headFade = 0.4
    /// Sensibilité au son de la barre : 0–10 = coupé, 11–255 = faible → forte (manuel de la 4BAR LT BT).
    /// ⚠︎ Comme les programmes, à confirmer au banc d'essai DMX.
    static let soundSensitivityRange: ClosedRange<Double> = 11...255

    /// Ce que fait la barre, avant le gradateur général et les projecteurs coupés à la main.
    struct Output: Equatable, Sendable {
        /// Canal programme : pilotage direct, programme automatique ou « sur le son ».
        var program: UInt8
        /// Canal 3 : strobo (pilotage direct), vitesse d'un programme, sensibilité au son.
        var aux: UInt8
        /// Niveau 0…1. En pilotage direct il est déjà dans `heads` ; pour un programme, c'est le gradateur qui le porte.
        var level: Double
        /// Rouge, vert, bleu de chaque projecteur (0…255, décimaux pour des fondus fins), niveau compris.
        var heads: [[Double]]
    }

    enum Scene: Equatable, Sendable {
        case black
        case look(LightLook, pad: UUID?, start: Double)
    }

    struct Transition: Equatable, Sendable {
        var from: Output
        var start: Double
        var duration: Double
    }

    struct HeadFade: Equatable, Sendable {
        var from: Double
        var to: Double
        var start: Double
    }

    /// L'appareil du spectacle (profil, adresse, durée du Noir).
    public var rig: DMXRig {
        didSet { if rig.profile.headCount != headFades.count { resetHeads() } }
    }
    /// Fader **Général** (0…1) : le gradateur de toute la barre, en direct.
    public var master: Double {
        get { masterLevel }
        set { masterLevel = Self.fraction(newValue) }
    }
    /// Fader **Couleurs** (0…1), **relatif** (décision du 27/11/2026) : sa position au moment où un état part donne les
    /// couleurs du pad ; le bouger ensuite fait tourner toutes les teintes ensemble sur la roue (toute la course = un tour).
    public var colorFader: Double {
        get { colorLevel }
        set { colorLevel = Self.fraction(newValue) }
    }
    /// Position du fader Couleurs quand l'état en cours est parti (son « origine »).
    public private(set) var colorReference = 1.0
    /// Rotation des teintes en cours, en tours (−1…1).
    public var colorShift: Double { colorLevel - colorReference }
    /// Strobo réglé en direct (0…1, 0 = arrêté) ; `nil` = celui de l'état joué. Sans effet sur un programme de la barre.
    public var strobeOverride: Double?
    /// Les temps du son qui donne le tempo (étape 3b) ; `nil` = tempo de repli de l'alternance, compté depuis son départ.
    public var beatClock: BeatClock?

    /// Tempo et instant d'un temps (de préférence un premier temps de mesure), en secondes de `DMXClock`.
    public struct BeatClock: Equatable, Sendable {
        public var bpm: Double
        public var origin: Double

        public init(bpm: Double, origin: Double) {
            self.bpm = bpm
            self.origin = origin
        }
    }

    private var masterLevel = 1.0
    private var colorLevel = 1.0
    private(set) var scene: Scene = .black
    private(set) var transition: Transition?
    private var headFades: [HeadFade] = []

    public init(rig: DMXRig) {
        self.rig = rig
        resetHeads()
    }

    // MARK: - Gestes

    /// Ce que la console joue, pour y revenir après un aperçu (étape 4e).
    public struct Snapshot: Equatable, Sendable {
        fileprivate let scene: Scene
        fileprivate let colorReference: Double
    }

    public var snapshot: Snapshot { Snapshot(scene: scene, colorReference: colorReference) }

    /// Revient à une lumière mémorisée, en fondu de `fade` secondes depuis la lumière en cours.
    public mutating func restore(_ snapshot: Snapshot, fade: Double, at time: Double) {
        startTransition(duration: fade, at: time)
        scene = snapshot.scene
        colorReference = snapshot.colorReference
    }

    /// L'état lumineux joué (`nil` : noir).
    public var activeLook: LightLook? {
        if case .look(let look, _, _) = scene { look } else { nil }
    }

    /// Remplace l'état joué sans fondu (le pad a été réglé pendant qu'il éclaire) ; l'alternance garde sa phase.
    public mutating func replaceActiveLook(_ look: LightLook) {
        guard case .look(_, let pad, let start) = scene else { return }
        scene = .look(look, pad: pad, start: start)
    }

    /// Le pad dont l'état est joué (`nil` : noir).
    public var activePad: UUID? {
        if case .look(_, let pad, _) = scene { pad } else { nil }
    }

    public var isBlack: Bool { scene == .black }

    /// Joue un état, en fondu de sa durée d'entrée depuis la lumière en cours.
    public mutating func play(_ look: LightLook, pad: UUID?, at time: Double) {
        startTransition(duration: look.fadeIn, at: time)
        scene = .look(look, pad: pad, start: time)
        colorReference = colorLevel
    }

    /// Éteint tout en fondu de `duration` secondes.
    public mutating func fadeToBlack(duration: Double, at time: Double) {
        startTransition(duration: duration, at: time)
        scene = .black
    }

    /// Noir : fondu de la durée réglée pour le spectacle (« Fondu du noir »).
    public mutating func blackout(at time: Double) {
        fadeToBlack(duration: rig.blackoutFade, at: time)
    }

    /// Allume ou coupe un projecteur (0 = le premier) en fondu, sur la lumière en cours, sans changer l'état joué.
    public mutating func setHead(_ index: Int, on: Bool, at time: Double) {
        guard headFades.indices.contains(index) else { return }
        headFades[index] = HeadFade(from: headMask(index, at: time), to: on ? 1 : 0, start: time)
    }

    public func isHeadOn(_ index: Int) -> Bool {
        headFades.indices.contains(index) && headFades[index].to > 0
    }

    // MARK: - Trame

    public func frame(at time: Double) -> DMXFrame {
        let profile = rig.profile
        let (out, dimmer) = finalOutput(at: time)
        var bytes = [UInt8](repeating: 0, count: profile.channelCount)
        for (offset, channel) in profile.channels.enumerated() {
            switch channel.role {
            case .program: bytes[offset] = out.program
            case .dimmer: bytes[offset] = Self.byte(255 * dimmer)
            case .strobe: bytes[offset] = out.aux
            case .red, .green, .blue:
                let head = channel.head - 1
                guard out.heads.indices.contains(head) else { continue }
                let component = channel.role == .red ? 0 : channel.role == .green ? 1 : 2
                bytes[offset] = Self.byte(out.heads[head][component])
            }
        }
        var frame = DMXFrame(length: rig.address + profile.channelCount - 1)
        frame.set(bytes, from: rig.address)
        return frame
    }

    /// Quand une alternance joue : son tempo (celui du son en cours, sinon le tempo de repli) et si l'on est sur un temps
    /// (pour le point qui bat sur la carte Général). `nil` pour tout autre état.
    public func alternationInfo(at time: Double) -> (bpm: Double, onBeat: Bool)? {
        guard case .look(let look, _, let start) = scene, case .alternate(let alternate) = look.content else { return nil }
        let bpm = min(max(beatClock?.bpm ?? alternate.fallbackBPM, 20), 400)
        let elapsed = beatClock.map { time + rig.lightLead - $0.origin } ?? max(time - start, 0)
        let beat = 60 / bpm
        let phase = (elapsed / beat).truncatingRemainder(dividingBy: 1)
        return (bpm, (phase < 0 ? phase + 1 : phase) < 0.3)
    }

    /// Couleur de chaque projecteur telle que la barre la montre (gradateur compris), pour la mini-barre de l'écran.
    /// Un programme de la barre choisit ses couleurs lui-même : elles sont alors inconnues (noires ici).
    public func headColors(at time: Double) -> [RGB] {
        let (out, dimmer) = finalOutput(at: time)
        return out.heads.map { RGB(red: Self.byte($0[0] * dimmer), green: Self.byte($0[1] * dimmer), blue: Self.byte($0[2] * dimmer)) }
    }

    // MARK: - Calcul

    /// La sortie à cet instant (fondu et projecteurs coupés compris) et le gradateur (0…1).
    private func finalOutput(at time: Double) -> (Output, Double) {
        var out = currentOutput(at: time)
        for index in out.heads.indices {
            let mask = headMask(index, at: time)
            if mask < 1 { out.heads[index] = out.heads[index].map { $0 * mask } }
        }
        let isDirect = out.program == rig.profile.directValue
        return (out, masterLevel * (isDirect ? 1 : out.level))
    }

    /// La lumière à cet instant, fondu en cours compris (sans les projecteurs coupés à la main).
    private func currentOutput(at time: Double) -> Output {
        let target = render(at: time)
        guard let transition, transition.duration > 0, time < transition.start + transition.duration else { return target }
        let p = min(max((time - transition.start) / transition.duration, 0), 1)
        let from = transition.from
        let toBlack = scene == .black
        let heads = target.heads.indices.map { head in
            let a = from.heads.indices.contains(head) ? from.heads[head] : [0, 0, 0]
            return (0..<3).map { a[$0] + (target.heads[head][$0] - a[$0]) * p }
        }
        return Output(
            program: toBlack ? from.program : target.program,
            aux: toBlack ? from.aux : target.aux,
            level: from.level + (target.level - from.level) * p,
            heads: heads)
    }

    private mutating func startTransition(duration: Double, at time: Double) {
        let from = currentOutput(at: time)
        let duration = duration.isFinite ? max(duration, 0) : 0
        transition = Transition(from: from, start: time, duration: duration)
    }

    private func render(at time: Double) -> Output {
        let profile = rig.profile
        let dark = [[Double]](repeating: [0, 0, 0], count: profile.headCount)
        switch scene {
        case .black:
            return Output(program: profile.directValue, aux: 0, level: 0, heads: dark)
        case .look(let look, _, let start):
            switch look.content {
            case .colors(let colors):
                let heads = (0..<profile.headCount).map { index -> [Double] in
                    guard colors.heads.indices.contains(index), colors.heads[index].isOn else { return [0, 0, 0] }
                    return rgb(colors.heads[index].color, intensity: colors.heads[index].intensity)
                }
                return Output(program: profile.directValue, aux: strobe(colors.strobe), level: 1, heads: heads)
            case .alternate(let alternate):
                return Output(
                    program: profile.directValue, aux: strobe(nil), level: 1,
                    heads: alternateHeads(alternate, since: start, at: time, count: profile.headCount))
            case .fixtureProgram(let number, let speed):
                return Output(
                    program: profile.programValue(number: number) ?? profile.directValue, aux: Self.byte(255 * Self.fraction(speed)),
                    level: 1, heads: dark)
            case .soundActive(let sensitivity):
                let range = Self.soundSensitivityRange
                return Output(
                    program: profile.soundActiveValue ?? profile.directValue,
                    aux: Self.byte(range.lowerBound + (range.upperBound - range.lowerBound) * Self.fraction(sensitivity)),
                    level: 1, heads: dark)
            }
        }
    }

    /// Alternance : projecteurs impairs (1, 3…) en A et pairs en B, échangés à chaque intervalle, avec un fondu à la bascule.
    /// Avec un son qui donne le tempo, les bascules tombent sur **ses** temps (mesure comptée depuis le temps de référence),
    /// en avance de `DMXRig.lightLead` ; sinon au tempo de repli, comptées depuis le départ de l'état.
    private func alternateHeads(_ look: AlternateLook, since start: Double, at time: Double, count: Int) -> [[Double]] {
        let bpm = min(max(beatClock?.bpm ?? look.fallbackBPM, 20), 400)
        let beats: Double =
            switch look.every {
            case .beat: 1
            case .twoBeats: 2
            case .bar: 4
            }
        let period = 60 / bpm * beats
        let elapsed = beatClock.map { time + rig.lightLead - $0.origin } ?? max(time - start, 0)
        let step = (elapsed / period).rounded(.down)
        let within = elapsed - step * period
        func arrangement(_ step: Double) -> [[Double]] {
            let even = step.truncatingRemainder(dividingBy: 2) == 0
            return (0..<count).map { index in rgb((index % 2 == 0) == even ? look.a : look.b, intensity: 1) }
        }
        let current = arrangement(step)
        guard beatClock != nil || step >= 1, look.switchFade > 0, within < look.switchFade else { return current }
        let previous = arrangement(step - 1)
        let p = within / look.switchFade
        return current.indices.map { head in (0..<3).map { previous[head][$0] + (current[head][$0] - previous[head][$0]) * p } }
    }

    /// Couleur d'un projecteur, rotation du fader Couleurs comprise (un blanc n'a pas de teinte : il reste blanc).
    private func rgb(_ color: LightColor, intensity: Double) -> [Double] {
        let shift = colorShift
        let turned = shift != 0 ? LightColor(hue: color.hue + shift * 360, saturation: color.saturation) : color
        let value = rig.profile.rgb(for: turned, intensity: intensity)
        return [Double(value.red), Double(value.green), Double(value.blue)]
    }

    private func strobe(_ own: Double?) -> UInt8 {
        guard let speed = strobeOverride ?? own else { return 0 }
        return rig.profile.strobeValue(speed: Self.fraction(speed))
    }

    private func headMask(_ index: Int, at time: Double) -> Double {
        guard headFades.indices.contains(index) else { return 1 }
        let fade = headFades[index]
        let p = min(max((time - fade.start) / Self.headFade, 0), 1)
        return fade.from + (fade.to - fade.from) * p
    }

    private mutating func resetHeads() {
        headFades = Array(repeating: HeadFade(from: 1, to: 1, start: 0), count: rig.profile.headCount)
    }

    private static func fraction(_ value: Double) -> Double { value.isNaN ? 0 : min(max(value, 0), 1) }

    private static func byte(_ value: Double) -> UInt8 { value.isNaN ? 0 : UInt8(min(max(value, 0), 255).rounded()) }
}

extension DMXFaderRole {
    /// Rôle du fader de chaque colonne lumière d'une grille (clé = numéro de colonne ; « Aucun » absent). Une colonne sans rôle
    /// choisi prend celui de son rang parmi les colonnes lumière : la 1re est **Général**, la 2e **Couleurs**, les suivantes
    /// n'ont pas de rôle. Deux colonnes au même rôle règlent la même chose.
    public static func roles(for grid: PadGrid) -> [Int: DMXFaderRole] {
        let lightColumns = grid.columns.indices.filter { grid.columns[$0].kind == .light }
        var result: [Int: DMXFaderRole] = [:]
        for (rank, index) in lightColumns.enumerated() {
            let fallback: DMXFaderRole = rank == 0 ? .general : rank == 1 ? .colors : .none
            let role = grid.columns[index].faderRole ?? fallback
            if role != .none { result[index] = role }
        }
        return result
    }

    /// Rôle effectif d'une colonne (`.none` si elle n'a pas de rôle ou n'est pas une colonne lumière).
    public static func role(ofColumn column: Int, in grid: PadGrid) -> DMXFaderRole {
        roles(for: grid)[column] ?? .none
    }
}

extension Show {
    /// Mode Projecteurs : un **seul** Général et un seul fader Couleurs pour tout le spectacle (décision du 27/11/2026) —
    /// changer de grille ne change jamais la lumière. Le niveau du fader `column` de la grille `grid`, s'il a un rôle, est
    /// recopié sur la colonne du même rôle de chaque grille.
    mutating func alignDMXFaders(from grid: Int, column: Int) {
        guard grids.indices.contains(grid), let role = DMXFaderRole.roles(for: grids[grid])[column] else { return }
        let level = grids[grid].columns[column].level
        for index in grids.indices {
            for (target, targetRole) in DMXFaderRole.roles(for: grids[index]) where targetRole == role {
                if index == grid, target == column { continue }
                grids[index].columns[target].level = level  // même rôle = même réglage, dans cette grille comme dans les autres
            }
        }
    }

    /// Aligne tous les faders à rôle sur ceux de la grille `grid` (passage en mode Projecteurs).
    mutating func alignAllDMXFaders(from grid: Int) {
        guard grids.indices.contains(grid) else { return }
        for column in DMXFaderRole.roles(for: grids[grid]).keys { alignDMXFaders(from: grid, column: column) }
    }
}
