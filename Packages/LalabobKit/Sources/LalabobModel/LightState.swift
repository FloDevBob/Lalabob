/// État d'une cue lumière tel que LightKey le renvoie. Vivant seulement : jamais écrit dans le spectacle.
public enum LightState: Sendable, Equatable {
    /// LightKey n'a encore rien dit sur cette case (pas appairée, ou LightKey fermé).
    case unknown
    case off
    case on
}
