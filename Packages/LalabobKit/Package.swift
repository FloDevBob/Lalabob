// swift-tools-version: 6.2
// LalabobKit : le cœur de Lalabob, indépendant de l'interface.
// Chaque module est une bibliothèque testable seule (voir docs/adr/0001-architecture.md).
import PackageDescription

let package = Package(
    name: "LalabobKit",
    defaultLocalization: "fr",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LalabobModel", targets: ["LalabobModel"]),
        .library(name: "LalabobDesign", targets: ["LalabobDesign"]),
        .library(name: "LalabobMIDI", targets: ["LalabobMIDI"]),
        .library(name: "ControllerDrivers", targets: ["ControllerDrivers"]),
        .library(name: "LalabobAudio", targets: ["LalabobAudio"]),
        .library(name: "LalabobEngine", targets: ["LalabobEngine"]),
    ],
    targets: [
        // Données pures : spectacle, grilles, pads, teintes. Aucune dépendance.
        .target(name: "LalabobModel"),
        // Jetons visuels (SwiftUI) dérivés de la maquette.
        .target(name: "LalabobDesign", dependencies: ["LalabobModel"]),
        // Messages MIDI (analyse / construction). CoreMIDI arrive au jalon 2.
        .target(name: "LalabobMIDI"),
        // Un pilote par contrôleur : notes ↔ cases, LED, faders.
        .target(name: "ControllerDrivers", dependencies: ["LalabobModel", "LalabobMIDI"]),
        // Lecture audio (AVAudioEngine) — jalon 1.
        .target(name: "LalabobAudio", dependencies: ["LalabobModel"]),
        // Orchestration : état du spectacle ouvert, commandes, routage.
        .target(
            name: "LalabobEngine",
            dependencies: ["LalabobModel", "LalabobAudio", "LalabobMIDI", "ControllerDrivers"]
        ),

        .testTarget(name: "LalabobModelTests", dependencies: ["LalabobModel"]),
        .testTarget(name: "LalabobMIDITests", dependencies: ["LalabobMIDI"]),
        .testTarget(name: "ControllerDriversTests", dependencies: ["ControllerDrivers", "LalabobModel", "LalabobMIDI"]),
    ],
    swiftLanguageModes: [.v6]
)
