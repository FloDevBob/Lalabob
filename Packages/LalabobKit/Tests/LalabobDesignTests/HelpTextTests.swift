import Testing

@testable import LalabobDesign

/// Infobulles qui dépendent d'un état : le texte suit l'état, le raccourci est toujours indiqué, et une action refusée
/// parce que le spectacle est verrouillé explique pourquoi.
@Suite("Textes d'infobulle")
struct HelpTextTests {
    @Test func lockTooltipFollowsTheStateAndMentionsTheShortcut() {
        #expect(HelpText.lock(locked: true).hasPrefix("Déverrouiller"))
        #expect(HelpText.lock(locked: false).hasPrefix("Verrouiller"))
        #expect(HelpText.lock(locked: true).contains("⌘L"))
        #expect(HelpText.lock(locked: false).contains("⌘L"))
    }

    @Test func editTooltipExplainsWhyWhenLocked() {
        #expect(HelpText.edit("Couper (⌘X)", locked: false) == "Couper (⌘X)")
        #expect(HelpText.edit("Couper (⌘X)", locked: true) == HelpText.lockedReason)
        #expect(HelpText.lockedReason.contains("cadenas"))
    }

    @Test func renameHintDisappearsWhenLocked() {
        #expect(HelpText.rename("le titre", locked: true).isEmpty)
        #expect(HelpText.rename("le titre", locked: false) == "Double-cliquer pour renommer le titre")
    }

    @Test func toggleTooltipsNameTheActionNotTheState() {
        #expect(HelpText.pause(isPaused: false) == "Pause")
        #expect(HelpText.pause(isPaused: true) == "Reprendre")
        #expect(HelpText.play(isPlaying: false) == "Lecture")
        #expect(HelpText.play(isPlaying: true).contains("Relancer"))
        #expect(HelpText.loop(isOn: false).hasPrefix("Activer"))
        #expect(HelpText.loop(isOn: true).hasPrefix("Désactiver"))
        #expect(HelpText.library(shown: true) == "Masquer la bibliothèque")
        #expect(HelpText.library(shown: false) == "Afficher la bibliothèque")
    }
}
