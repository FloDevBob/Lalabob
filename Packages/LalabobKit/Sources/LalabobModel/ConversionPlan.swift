import Foundation

/// Ce qu'un changement de type de colonne ou de pad retire (fiche 06). Pur : la même fonction sert à écrire la feuille de
/// confirmation (fiche 07) et à faire la conversion, pour que l'une ne puisse pas mentir sur l'autre.
///
/// Principe : **élargir ne retire rien, restreindre retire ce qui ne rentre plus**. Un plan « sans perte » ne demande aucune
/// confirmation.
public struct ConversionPlan: Equatable, Sendable {
    /// Pads supprimés : le nouveau type n'a rien à en garder.
    public var deletedPads: [Pad] = []
    /// Pads qui restent mais **perdent leur cue appairée** (son et lumière → son) : l'appairage est oublié côté Lalabob,
    /// rien n'est changé dans LightKey.
    public var padsLosingLight: [Pad] = []
    /// Pads qui restent mais **perdent leur son** et ses réglages (son et lumière → lumière, son → lumière).
    public var padsLosingSound: [Pad] = []
    /// La colonne quitte « Lumière » alors que son fader était appairé : l'appairage est oublié.
    public var faderPairingForgotten = false
    /// La colonne devient « Lumière » alors que son filtre n'était pas neutre : il revient au neutre.
    public var filterReset = false

    public init() {}

    /// Rien n'est perdu : aucune confirmation à demander.
    public var isLossless: Bool {
        deletedPads.isEmpty && padsLosingLight.isEmpty && padsLosingSound.isEmpty && !faderPairingForgotten && !filterReset
    }

    /// Nombre de pads touchés d'une façon ou d'une autre (pour une phrase d'ensemble).
    public var affectedPadCount: Int { deletedPads.count + padsLosingLight.count + padsLosingSound.count }

    // MARK: - Plans

    /// Ce que coûte le passage d'une colonne à un autre type.
    public static func column(_ column: Column, to kind: ColumnKind) -> ConversionPlan {
        var plan = ConversionPlan()
        guard kind != column.kind else { return plan }
        for pad in column.slots.compactMap({ $0 }) {
            plan.record(pad, becoming: column.convertedPad(pad, to: kind))
        }
        plan.faderPairingForgotten = column.kind == .light && column.isFaderPaired
        plan.filterReset = kind == .light && column.kind != .light && column.filter != 0
        return plan
    }

    /// Ce que coûte le passage d'un pad à un autre type (dans une colonne mixte).
    public static func pad(_ pad: Pad, to kind: PadKind) -> ConversionPlan {
        var plan = ConversionPlan()
        plan.record(pad, becoming: pad.converted(to: kind))
        return plan
    }

    private mutating func record(_ before: Pad, becoming after: Pad?) {
        guard let after else {
            deletedPads.append(before)
            return
        }
        if before.audio != nil, after.audio == nil { padsLosingSound.append(before) }
        if before.light?.isPaired == true, after.light == nil { padsLosingLight.append(before) }
    }
}

extension Pad {
    /// Le pad une fois converti, ou `nil` s'il disparaît (rien à en garder).
    ///
    /// - vers **son** : retire la cue ; un pad lumière, ou « en attente de son », n'a pas de son à garder → `nil` ;
    /// - vers **lumière** : retire le son ; un pad son reçoit une cue vierge non appairée ;
    /// - vers **son et lumière** : un pad son reçoit une cue vierge ; un pad lumière attend son son (`awaitsSound`).
    ///
    /// Titre, sous-titre, teinte et intensité de LED sont toujours gardés.
    public func converted(to target: PadKind) -> Pad? {
        var pad = self
        switch target {
        case .audio:
            guard audio != nil else { return nil }
            pad.light = nil
            pad.awaitsSound = false
        case .light:
            if pad.light == nil { pad.light = .blank }
            pad.audio = nil
            pad.awaitsSound = false
        case .mixed:
            if pad.light == nil {
                pad.light = .blank
            } else if pad.audio == nil {
                pad.awaitsSound = true
            }
        }
        return pad
    }
}

extension Column {
    /// Ce que devient un pad de cette colonne quand elle change de type (`nil` = supprimé).
    /// Vers « lumière », les pads son sont supprimés (alors qu'un pad changé de type tout seul reçoit une cue vierge) :
    /// convertir toute une colonne ne fabrique pas des cues vides.
    func convertedPad(_ pad: Pad, to kind: ColumnKind) -> Pad? {
        switch kind {
        case .mixed:
            return pad
        case .audio:
            return pad.kind == .audio ? pad : pad.converted(to: .audio)
        case .light:
            switch pad.kind {
            case .light: return pad
            case .audio: return nil
            case .mixed: return pad.converted(to: .light)
            }
        }
    }

    /// La colonne convertie : pads convertis, volume ou intensité remis à leur valeur de départ quand le fader change de rôle
    /// (volume ↔ MIDI vers LightKey), appairage du fader et filtre oubliés quand ils n'ont plus de sens.
    public func converted(to kind: ColumnKind) -> Column {
        guard kind != self.kind else { return self }
        var column = self
        column.kind = kind
        column.slots = slots.map { $0.flatMap { convertedPad($0, to: kind) } }
        if kind == .light {
            column.filter = 0
            column.level = 1
        } else if self.kind == .light {
            column.level = 0.8
            column.isFaderPaired = false
        }
        return column
    }
}

extension LightCue {
    /// Une cue vierge, non appairée. La note envoyée à LightKey est celle du contrôleur (ADR 0006) : le message stocké ne sert pas.
    public static var blank: LightCue {
        LightCue(output: MIDIMessageSpec(kind: .note, channel: 0, number: 0))
    }
}
