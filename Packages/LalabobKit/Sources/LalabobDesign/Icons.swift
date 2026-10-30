import AppKit
import CoreText
import SwiftUI

/// Icônes de l'interface : jeu Iconoir (trait de 1,5, MIT), plus le projecteur et le cadenas ouvert dessinés
/// dans le même style. Ce sont des images « modèles » : elles prennent la couleur de `foregroundStyle`.
/// Voir ADR 0005.
public enum Icon: String, CaseIterable, Sendable {
    case play, pause, stop, restart, loop
    case cut, copy, duplicate, paste, trash
    case plus, close, folder, search, sidebar
    case sun, music, note, lock, lockOpen, volume, warning, wave, stopAll, spotlight

    var assetName: String { "icon-\(rawValue)" }

    public var image: Image { Image(assetName, bundle: .module) }

    /// L'icône à une taille donnée (les images d'actifs ne suivent pas la taille de la police).
    public func view(size: CGFloat = 16) -> some View {
        image.resizable().renderingMode(.template).aspectRatio(contentMode: .fit).frame(width: size, height: size)
    }
}

/// Étiquette texte + icône Iconoir.
public struct IconLabel: View {
    let title: LocalizedStringKey
    let icon: Icon
    let size: CGFloat

    public init(_ title: LocalizedStringKey, icon: Icon, size: CGFloat = 16) {
        self.title = title
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        Label { Text(title) } icon: { icon.view(size: size) }
    }
}

extension Button where Label == IconLabel {
    /// `Button("Copier", icon: .copy) { … }`
    @MainActor
    public init(_ title: LocalizedStringKey, icon: Icon, size: CGFloat = 16, action: @escaping () -> Void) {
        self.init(action: action) { IconLabel(title, icon: icon, size: size) }
    }
}

/// Polices livrées avec l'app (enregistrées pour le processus, sans toucher à Info.plist).
public enum Fonts {
    /// Famille de la police du logo.
    public static let logoFamily = "Fredoka"

    private static let registration: Void = {
        guard let url = Bundle.module.url(forResource: "Fredoka", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    /// À appeler au lancement ; sans effet après la première fois.
    public static func register() {
        _ = registration
    }
}
