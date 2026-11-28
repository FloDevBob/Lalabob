import Foundation

/// Les apps qui peuvent capter le son de Music en même temps que le pont audio (ADR 0011). Deux captures du même processus :
/// le son arrive en double (écho) ou muet dans Lalabob. Relevé du 28/11/2026 : Audio Hijack ouvert sur Music.
public enum CaptureAppConflicts {
    /// Préfixe d'identifiant d'app (sans tenir compte de la casse : un agent en arrière-plan est reconnu aussi) → nom affiché.
    static let known: [(prefix: String, name: String)] = [
        ("com.rogueamoeba.audiohijack", "Audio Hijack"),  // vérifié sur le Mac de régie
        ("com.rogueamoeba.loopback", "Loopback"),
        ("com.rogueamoeba.soundsource", "SoundSource"),
        ("com.rogueamoeba.piezo", "Piezo"),
    ]

    /// Les noms des apps de capture parmi ces identifiants d'apps ouvertes, sans doublon, dans l'ordre de `known`.
    public static func names(in bundleIDs: [String]) -> [String] {
        let running = bundleIDs.map { $0.lowercased() }
        return known.filter { app in running.contains { $0 == app.prefix || $0.hasPrefix(app.prefix + ".") } }.map(\.name)
    }

    /// Phrase d'avertissement, ou `nil` si aucune app de capture n'est ouverte.
    public static func warning(for names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let list = ListFormatter.localizedString(byJoining: names)
        let verb = names.count > 1 ? "sont ouverts" : "est ouvert"
        return "\(list) \(verb) : s'il capte Music, le son arrivera en double (écho) ou muet dans Lalabob. Arrêtez sa session sur Music ou fermez-le."
    }
}
