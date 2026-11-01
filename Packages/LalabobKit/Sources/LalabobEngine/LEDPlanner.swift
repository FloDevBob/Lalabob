import ControllerDrivers
import LalabobAudio
import LalabobModel

/// Décide de l'état de chaque LED du contrôleur à partir de la grille affichée. Pur et testable.
enum LEDPlanner {
    /// État voulu pour les 64 cases.
    /// - case vide : éteinte ; pad : sa teinte à son intensité ;
    /// - son en lecture : pulsation ; son en pause : teinte atténuée ;
    /// - cue lumière : allumée dans LightKey = pulsation, éteinte = teinte atténuée, état inconnu = teinte à son intensité.
    static func states(
        for grid: PadGrid, playback: [Pad.ID: PlaybackEvent], lightStates: [GridPosition: LightState] = [:]
    ) -> [GridPosition: LEDState] {
        var states: [GridPosition: LEDState] = [:]
        for position in GridPosition.all {
            guard let pad = grid[position] else {
                states[position] = .off
                continue
            }
            switch playback[pad.id]?.state {
            case .playing: states[position] = .pulsing(pad.tint)
            case .paused: states[position] = .lit(pad.tint, .quarter)
            case .idle, nil:
                switch pad.kind == .light ? lightStates[position] ?? .unknown : .unknown {
                case .on: states[position] = .pulsing(pad.tint)
                case .off: states[position] = .lit(pad.tint, .quarter)
                case .unknown: states[position] = .lit(pad.tint, pad.ledIntensity)
                }
            }
        }
        return states
    }

    /// Les LED à mettre à jour pour passer de `old` à `new`.
    static func changes(from old: [GridPosition: LEDState], to new: [GridPosition: LEDState]) -> [GridPosition: LEDState] {
        new.filter { old[$0.key] != $0.value }
    }
}
