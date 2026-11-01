import SwiftUI

extension View {
    /// Curseur de la souris au survol. `enabled == false` (verrouillé, désactivé) : le curseur par défaut, pour ne pas
    /// promettre une action qui n'aura pas lieu. À réserver aux zones sans apparence de bouton système (onglets,
    /// pastilles, poignées) : les boutons du système gardent la flèche, comme partout dans macOS.
    public func interactiveCursor(_ style: PointerStyle, enabled: Bool = true) -> some View {
        modifier(InteractiveCursor(style: style, enabled: enabled))
    }

    /// Éclaircit légèrement le fond au survol (onglets, boutons d'en-tête, lignes de la bibliothèque). Pas de mouvement,
    /// pas d'animation : le retour est immédiat. Jamais sur les pads ni les vumètres (sobriété en spectacle).
    public func hoverHighlight(cornerRadius: CGFloat = 8, enabled: Bool = true) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, enabled: enabled))
    }
}

/// Un contrôle désactivé (`.disabled`) retrouve tout seul le curseur par défaut.
private struct InteractiveCursor: ViewModifier {
    let style: PointerStyle
    let enabled: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.pointerStyle(enabled && isEnabled ? style : nil)
    }
}

private struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    let enabled: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(hovering && enabled && isEnabled ? 0.07 : 0)),
                alignment: .center
            )
            .onHover { hovering = $0 }
    }
}

/// Textes d'infobulle qui dépendent d'un état : purs, donc testables. Forme : verbe d'action, raccourci entre parenthèses.
public enum HelpText {
    /// Cadenas (⌘L).
    public static func lock(locked: Bool) -> String {
        locked
            ? "Déverrouiller pour modifier le spectacle (⌘L)"
            : "Verrouiller pour jouer sans risque (⌘L)"
    }

    /// Bibliothèque de sons.
    public static func library(shown: Bool) -> String {
        shown ? "Masquer la bibliothèque" : "Afficher la bibliothèque"
    }

    /// Explication donnée à la place d'une action refusée parce que le spectacle est verrouillé.
    public static let lockedReason = "Spectacle verrouillé : ouvrez le cadenas pour modifier (⌘L)"

    /// Texte d'une action de modification : l'action quand c'est possible, sinon la raison du refus.
    public static func edit(_ action: String, locked: Bool) -> String {
        locked ? lockedReason : action
    }

    /// Titre / sous-titre / nom : l'astuce du double-clic, absente quand c'est verrouillé.
    public static func rename(_ what: String, locked: Bool) -> String {
        locked ? "" : "Double-cliquer pour renommer \(what)"
    }

    /// Pause / reprise.
    public static func pause(isPaused: Bool) -> String { isPaused ? "Reprendre" : "Pause" }

    /// Lecture / relance.
    public static func play(isPlaying: Bool) -> String { isPlaying ? "Relancer depuis le début" : "Lecture" }

    /// Boucle.
    public static func loop(isOn: Bool) -> String { isOn ? "Désactiver la boucle" : "Activer la boucle" }
}
