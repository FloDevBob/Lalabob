import Foundation
import LalabobAudio
import Observation

/// Pré-écoute de la bibliothèque : un seul son à la fois, sur la sortie choisie pour le spectacle,
/// refusée quand le spectacle est verrouillé (on ne doit rien faire sonner par erreur sur scène).
@MainActor
@Observable
public final class PreviewController {
    public private(set) var playingItem: AudioLibraryItem.ID?
    /// Avancement de 0 à 1 (mis à jour par `refreshProgress()`).
    public private(set) var progress: Double = 0
    public private(set) var error: String?

    @ObservationIgnored private let previewer: any AudioPreviewing

    public init(previewer: any AudioPreviewing) {
        self.previewer = previewer
        previewer.onFinish = { [weak self] in
            self?.playingItem = nil
            self?.progress = 0
        }
    }

    public convenience init() {
        self.init(previewer: AVAudioPreviewer())
    }

    /// Lance le son, ou l'arrête s'il joue déjà. Verrouillé : arrête et ne lance rien.
    public func toggle(_ item: AudioLibraryItem, deviceUID: String?, isLocked: Bool) {
        error = nil
        if isLocked {
            stop()
            return
        }
        if playingItem == item.id {
            stop()
            return
        }
        stop()
        do {
            try previewer.play(url: item.url, deviceUID: deviceUID)
            playingItem = item.id
        } catch {
            self.error = "Impossible de pré-écouter « \(item.name) »."
        }
    }

    public func stop() {
        previewer.stop()
        playingItem = nil
        progress = 0
    }

    public func refreshProgress() {
        guard playingItem != nil, previewer.duration > 0 else {
            progress = 0
            return
        }
        progress = min(max(previewer.currentTime / previewer.duration, 0), 1)
    }

    public func dismissError() {
        error = nil
    }
}
