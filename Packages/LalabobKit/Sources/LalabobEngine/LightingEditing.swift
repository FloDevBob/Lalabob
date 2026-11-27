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
        let changed = commit("Modifier la lumière") { show, grid in
            guard position.isValid, var pad = show.grids[grid][position], var cue = pad.light, cue.look != look else { return false }
            cue.look = look
            pad.light = cue
            show.grids[grid][position] = pad
            return true
        }
        if changed { previewLook(at: position, look) }  // le réglage se voit tout de suite sur la barre
        return changed
    }

    /// Aperçu en direct (étape 4e) : applique cet état à la barre tout de suite, sans fondu et sans le désigner comme joué ;
    /// `endLookPreview()` rend la lumière d'avant. Jamais verrouillé ni en mode LightKey ; sans effet si l'état n'est pas jouable.
    public func previewLook(at position: GridPosition, _ look: LightLook) {
        guard isDMXLighting, !isLocked, position.isValid, look.isValid(for: show.lighting.rig.profile),
            let pad = pad(at: position), pad.light != nil
        else { return }
        dmxHandler?(.preview(pad.id, look))
    }

    /// Fin de l'aperçu (on quitte le pad) : la barre revient en fondu à la lumière qui était en cours.
    public func endLookPreview() {
        dmxHandler?(.endPreview)
    }

    /// L'état lumineux que jouerait ce pad aujourd'hui (le sien, ou la couleur de son pad), où qu'il soit dans le spectacle.
    func committedLook(ofPad id: Pad.ID) -> LightLook? {
        let headCount = show.lighting.rig.profile.headCount
        for grid in show.grids {
            for column in grid.columns {
                for case let pad? in column.slots where pad.id == id {
                    guard let cue = pad.light else { return nil }
                    return cue.look ?? DMXSession.fallbackLook(for: pad, headCount: headCount)
                }
            }
        }
        return nil
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

    // MARK: - Rôle des faders lumière (étape 4d)

    /// Choisit ce que règle le fader d'une colonne lumière de la grille affichée (Général, Couleurs, Strobo, Aucun). La colonne
    /// reprend le niveau déjà réglé pour ce rôle, pour que la lumière ne bouge pas. Une annulation ; refusé verrouillé.
    @discardableResult
    public func setFaderRole(column: Int, to role: DMXFaderRole) -> Bool {
        commit("Rôle du fader") { show, grid in
            guard show.grids[grid].columns.indices.contains(column), show.grids[grid].columns[column].kind == .light,
                DMXFaderRole.role(ofColumn: column, in: show.grids[grid]) != role
            else { return false }
            show.grids[grid].columns[column].faderRole = role
            if role != .none {
                // Le niveau déjà réglé pour ce rôle (dans cette grille d'abord, puis dans les autres).
                let ordered = [grid] + show.grids.indices.filter { $0 != grid }
                for index in ordered {
                    let holder = DMXFaderRole.roles(for: show.grids[index]).first { $0.value == role && !(index == grid && $0.key == column) }
                    if let holder {
                        show.grids[grid].columns[column].level = show.grids[index].columns[holder.key].level
                        break
                    }
                }
            }
            return true
        }
    }
}
