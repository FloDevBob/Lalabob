// swift-tools-version: 6.2
// Fabrique le spectacle d'entraînement du tutoriel (Entraînement.lalabob) avec le modèle de Lalabob :
// le fichier passe donc par Show.validate() et le même encodage que l'app.
import PackageDescription

let package = Package(
    name: "GenerateTrainingShow",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../../Packages/LalabobKit")],
    targets: [
        .executableTarget(
            name: "GenerateTrainingShow",
            dependencies: [.product(name: "LalabobModel", package: "LalabobKit")]
        )
    ],
    swiftLanguageModes: [.v6]
)
