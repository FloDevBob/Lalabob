import LalabobEngine
import SwiftUI

extension FocusedValues {
    /// Le spectacle de la fenêtre active, pour les commandes des menus.
    @Entry var showController: ShowController?
}

/// Menus : ⌘L (cadenas), ⌘D (dupliquer le pad), onglets ⌘1…⌘9, nouvelle grille ⌘T.
/// ⌘X, ⌘C, ⌘V et ⌫ passent par la grille (`onCopyCommand`…), pour ne pas gêner les champs de texte.
struct LalabobCommands: Commands {
    static let benchWindowID = "lighting-bench"
    static let dmxBenchWindowID = "dmx-bench"
    static let helpWindowID = "help"

    @FocusedValue(\.showController) private var controller
    @FocusedValue(\.showSettingsPresented) private var showSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openDocument) private var openDocument

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button("Dupliquer le pad") { controller?.duplicateSelection() }
                .keyboardShortcut("d")
                .disabled(controller?.selection == nil || controller?.isLocked == true)
        }
        // Menu Aide : l'aide de l'app remplace l'entrée par défaut (qui ne trouve aucun Help Book).
        CommandGroup(replacing: .help) {
            Button("Aide de Lalabob") { openWindow(id: Self.helpWindowID) }
                .keyboardShortcut("?", modifiers: .command)
            Divider()
            Button("Visite guidée") { openWindow(id: Tour.windowID) }
            Button("Ouvrir le spectacle d'entraînement") {
                Task { await Tour.openTrainingShow(with: openDocument) }
            }
        }
        CommandGroup(after: .windowArrangement) {
            Button("Banc d'essai lumière") { openWindow(id: Self.benchWindowID) }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button("Banc d'essai DMX") { openWindow(id: Self.dmxBenchWindowID) }
        }
        CommandMenu("Spectacle") {
            Button(controller?.isLocked == true ? "Déverrouiller" : "Verrouiller") { controller?.isLocked.toggle() }
                .keyboardShortcut("l")
                .disabled(controller == nil)
            Divider()
            Button("Réglages du spectacle…") { showSettings?.wrappedValue = true }
                .keyboardShortcut(",", modifiers: [.command, .option])
                .disabled(showSettings == nil || controller?.isLocked != false)
        }
        CommandMenu("Grilles") {
            Button("Nouvelle grille") { controller?.addGrid() }
                .keyboardShortcut("t")
                .disabled(controller?.isLocked != false)
            Button("Nouvelle grille Apple Music") { controller?.addGrid(kind: .appleMusic) }
                .keyboardShortcut("t", modifiers: [.command, .option])
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
