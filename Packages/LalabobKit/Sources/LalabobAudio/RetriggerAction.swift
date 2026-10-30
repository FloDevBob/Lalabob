import LalabobModel

/// Ce que fait le moteur quand on appuie sur un pad, selon son état.
public enum RetriggerAction: Equatable, Sendable {
    case start
    case restart
    case stop
    case resume

    public static func resolve(state: PlaybackState, behavior: RetriggerBehavior) -> RetriggerAction {
        switch state {
        case .idle: .start
        case .paused: .resume
        case .playing: behavior == .restart ? .restart : .stop
        }
    }
}
