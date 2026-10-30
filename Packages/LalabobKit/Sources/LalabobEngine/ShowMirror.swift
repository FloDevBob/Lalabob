import Foundation
import LalabobModel
import Synchronization

/// Copie du spectacle lisible depuis n'importe quel fil : SwiftUI enregistre le document en arrière-plan,
/// alors que `ShowController` vit sur le fil principal. `ShowController.onShowChange` la tient à jour.
public final class ShowMirror: Sendable {
    private let state: Mutex<Show>

    public init(_ show: Show) {
        state = Mutex(show)
    }

    public var current: Show { state.withLock { $0 } }

    public func update(_ show: Show) {
        state.withLock { $0 = show }
    }
}
