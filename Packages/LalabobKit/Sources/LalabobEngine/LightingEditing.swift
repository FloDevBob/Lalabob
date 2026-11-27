import Foundation
import LalabobModel

/// Réglages lumière du spectacle (J14, ADR 0012) : mode LightKey ou Projecteurs, appareil DMX. Passent par `commit`
/// (⌘Z, refusés verrouillé). L'interface est dans Réglages du spectacle (`ShowSettingsView`).
extension ShowController {
    /// Choisit qui pilote la lumière. Passer en Projecteurs aligne les faders Général et Couleurs de toutes les grilles sur
    /// la grille affichée, et quitte le mode « Relier aux projecteurs » (inutile en DMX).
    public func setLightingMode(_ mode: LightingMode) {
        let changed = commit(mode == .dmx ? "Projecteurs pilotés par Lalabob" : "Logiciel lumière") { show, grid in
            guard show.lighting.mode != mode else { return false }
            show.lighting.mode = mode
            if mode == .dmx { show.alignAllDMXFaders(from: grid) }  // un seul Général, une seule rotation des couleurs
            return true
        }
        if changed, mode == .dmx, isPairingLights { setPairingLights(false) }
    }

    /// Remplace l'appareil DMX du spectacle (adresse bornée au profil, fondu du noir borné).
    public func setDMXRig(_ rig: DMXRig) {
        let clamped = DMXRig(
            profile: rig.profile, address: rig.address,
            blackoutFade: min(max(rig.blackoutFade.isFinite ? rig.blackoutFade : 1.5, DMXRig.blackoutFadeRange.lowerBound),
                DMXRig.blackoutFadeRange.upperBound),
            onQuit: rig.onQuit, favoriteColors: Array(rig.favoriteColors.prefix(DMXRig.maximumFavoriteColors)),
            lightLead: rig.lightLead)
        commit("Réglages des projecteurs") { show, _ in
            guard show.lighting.rig != clamped else { return false }
            show.lighting.rig = clamped
            return true
        }
    }

    // MARK: - États lumineux (étape 4c)

    /// L'état lumineux que jouerait ce pad : le sien, ou — pour une cue créée avec LightKey — les projecteurs à la couleur
    /// du pad. `nil` sur une case qui n'est pas une lumière.
    public func effectiveLook(at position: GridPosition) -> LightLook? {
        guard position.isValid, let pad = pad(at: position), let cue = pad.light else { return nil }
        return cue.look ?? DMXSession.fallbackLook(for: pad, headCount: show.lighting.rig.profile.headCount)
    }

    /// Remplace l'état lumineux d'un pad lumière (le premier réglage d'une cue sans état la fait passer au sien). Refusé si
    /// l'état n'est pas jouable par l'appareil du spectacle (mauvais nombre de projecteurs, valeurs hors bornes). Une annulation.
    @discardableResult
    public func setLook(at position: GridPosition, to look: LightLook) -> Bool {
        let profile = show.lighting.rig.profile
        guard look.isValid(for: profile) else { return false }
        return commit("Modifier la lumière") { show, grid in
            guard position.isValid, var pad = show.grids[grid][position], var cue = pad.light, cue.look != look else { return false }
            cue.look = look
            pad.light = cue
            show.grids[grid][position] = pad
            return true
        }
    }

    /// Change le type de l'état (Couleurs · Alternance · Programme · Sur le son) en gardant ce qui se garde.
    @discardableResult
    public func setLookStyle(at position: GridPosition, to style: LightLook.Content.Style) -> Bool {
        let profile = show.lighting.rig.profile
        guard let look = effectiveLook(at: position)?.converted(to: style, profile: profile) else { return false }
        return setLook(at: position, to: look)
    }

    /// Garde (ou retire) une couleur dans les favoris du spectacle, sous la roue. Une annulation.
    @discardableResult
    public func toggleFavoriteColor(_ color: LightColor) -> Bool {
        var rig = show.lighting.rig
        if let index = rig.favoriteColors.firstIndex(of: color) {
            rig.favoriteColors.remove(at: index)
        } else {
            guard rig.favoriteColors.count < DMXRig.maximumFavoriteColors else { return false }
            rig.favoriteColors.append(color)
        }
        return commit("Couleurs du spectacle") { show, _ in
            show.lighting.rig = rig
            return true
        }
    }
}
