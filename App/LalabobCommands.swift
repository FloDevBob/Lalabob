import LalabobEngine
import SwiftUI

extension FocusedValues {
    /// Le spectacle de la fenêtre active, pour les commandes des menus.
    @Entry var showController: ShowController?
}

/// Menus : ⌘L (cadenas), ⌘D (dupliquer le pad), onglets ⌘1…⌘9, nouvelle grille ⌘T.
/// ⌘X, ⌘C, ⌘V et ⌫ passent par la grille (`onCopyCommand`…), pour ne pas gêner les champs de texte.
struct LalabobCommands: Commands {
    @FocusedValue(\.showController) private var controller

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Dupliquer le pad") { controller?.duplicateSelection() }
                .keyboardShortcut("d")
                .disabled(controller?.selection == nil || controller?.isLocked == true)
        }
        CommandMenu("Spectacle") {
            Button(controller?.isLocked == true ? "Déverrouiller" : "Verrouiller") { controller?.isLocked.toggle() }
                .keyboardShortcut("l")
                .disabled(controller == nil)
        }
        CommandMenu("Grilles") {
            Button("Nouvelle grille") { controller?.addGrid() }
                .keyboardShortcut("t")
                .disabled(controller?.isLocked != false)
            Divider()
            ForEach(1...9, id: \.self) { number in
                Button("Grille \(number)") { controller?.selectGrid(at: number - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                    .disabled((controller?.show.grids.count ?? 0) < number)
            }
        }
    }
}
