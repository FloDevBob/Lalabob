import Foundation
import LalabobModel

/// Réglages lumière du spectacle (J14, ADR 0012) : mode LightKey ou Projecteurs, appareil DMX. Passent par `commit`
/// (⌘Z, refusés verrouillé). L'interface (Réglages du spectacle) viendra à l'étape 4.
extension ShowController {
    /// Choisit qui pilote la lumière. Passer en Projecteurs quitte le mode « Relier aux projecteurs » (inutile en DMX).
    public func setLightingMode(_ mode: LightingMode) {
        let changed = commit(mode == .dmx ? "Projecteurs pilotés par Lalabob" : "Logiciel lumière") { show, _ in
            guard show.lighting.mode != mode else { return false }
            show.lighting.mode = mode
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
            onQuit: rig.onQuit, favoriteColors: Array(rig.favoriteColors.prefix(DMXRig.maximumFavoriteColors)))
        commit("Réglages des projecteurs") { show, _ in
            guard show.lighting.rig != clamped else { return false }
            show.lighting.rig = clamped
            return true
        }
    }
}
