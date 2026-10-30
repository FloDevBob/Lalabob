import Foundation
import Testing

@testable import LalabobModel

@Suite("Paquet .lalabob")
struct ShowPackageTests {
    private func sampleShow() -> Show {
        var show = Show.new(name: "Match du 14 novembre")
        show.grids[0][GridPosition(column: 0, row: 0)] = Pad(
            title: "Rire", tint: .vert, content: .audio(clip: AudioClip(fileName: "rire.wav")))
        return show
    }

    @Test("Écrire puis relire un paquet redonne le même spectacle et garde les sons")
    func roundTrip() throws {
        let show = sampleShow()
        let audio = FileWrapper(directoryWithFileWrappers: ["rire.wav": FileWrapper(regularFileWithContents: Data([1, 2, 3]))])
        let package = try ShowPackage.wrapper(for: show, audio: audio)

        #expect(package.isDirectory)
        #expect(package.fileWrappers?[ShowPackage.showFileName]?.isRegularFile == true)
        let read = try ShowPackage.read(package)
        #expect(read.show == show)
        #expect(read.audioFileNames == ["rire.wav"])
        #expect(read.missingAudio.isEmpty)
    }

    @Test("Le JSON est lisible et stable (clés triées)")
    func stableJSON() throws {
        let data = try ShowPackage.encode(sampleShow())
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\n"))
        let again = try ShowPackage.encode(try ShowPackage.decode(data))
        #expect(again == data)
    }

    @Test("Un son référencé mais absent est signalé, sans empêcher l'ouverture")
    func missingAudio() throws {
        let package = try ShowPackage.wrapper(for: sampleShow(), audio: nil)
        let read = try ShowPackage.read(package)
        #expect(read.missingAudio == ["rire.wav"])
    }

    @Test("Un dossier sans show.json est refusé")
    func noShowFile() {
        let package = FileWrapper(directoryWithFileWrappers: [:])
        #expect(throws: ShowPackageError.missingShowFile) { try ShowPackage.read(package) }
    }

    @Test("Un fichier qui n'est pas un dossier est refusé")
    func notAPackage() {
        let file = FileWrapper(regularFileWithContents: Data("{}".utf8))
        #expect(throws: ShowPackageError.notAPackage) { try ShowPackage.read(file) }
    }

    @Test("Un JSON illisible est refusé")
    func corruptJSON() {
        let package = FileWrapper(directoryWithFileWrappers: [
            ShowPackage.showFileName: FileWrapper(regularFileWithContents: Data("pas du json".utf8))
        ])
        #expect(throws: ShowPackageError.corrupt) { try ShowPackage.read(package) }
    }

    @Test("Un show.json démesuré est refusé avant d'être décodé")
    func oversized() {
        let huge = Data(repeating: 0x20, count: ShowPackage.maximumShowFileSize + 1)
        #expect(throws: ShowPackageError.tooLarge) { try ShowPackage.decode(huge) }
    }

    @Test("Un spectacle invalide est refusé à l'ouverture (validate)")
    func invalidShowIsRejected() throws {
        var show = sampleShow()
        show.grids[0][GridPosition(column: 1, row: 0)] = Pad(
            title: "Piège", tint: .rouge, content: .audio(clip: AudioClip(fileName: "../../secret.wav")))
        let data = try JSONEncoder().encode(show)
        #expect(throws: ShowPackageError.invalid(.unsafeFileName("../../secret.wav"))) { try ShowPackage.decode(data) }
    }

    @Test("Les fichiers du dossier Audio aux noms dangereux sont ignorés")
    func unsafeAudioNamesAreIgnored() throws {
        let audio = FileWrapper(directoryWithFileWrappers: [
            "rire.wav": FileWrapper(regularFileWithContents: Data([1])),
            ".DS_Store": FileWrapper(regularFileWithContents: Data([1])),
            "sous-dossier": FileWrapper(directoryWithFileWrappers: [:]),
        ])
        let read = try ShowPackage.read(try ShowPackage.wrapper(for: sampleShow(), audio: audio))
        #expect(read.audioFileNames == ["rire.wav"])
    }

    @Test("Écrire en ajoutant des sons conserve ceux qui y étaient")
    func addingAudioKeepsExistingFiles() throws {
        let existing = FileWrapper(directoryWithFileWrappers: ["rire.wav": FileWrapper(regularFileWithContents: Data([1]))])
        let added = ["porte.wav": FileWrapper(regularFileWithContents: Data([2]))]
        let package = try ShowPackage.wrapper(for: sampleShow(), audio: existing, adding: added)
        let names = package.fileWrappers?[ShowPackage.audioFolderName]?.fileWrappers?.keys.sorted()
        #expect(names == ["porte.wav", "rire.wav"])
    }
}

@Suite("Noms de fichiers audio importés")
struct AudioFileNameTests {
    @Test(
        "Un nom de fichier quelconque devient un nom sûr",
        arguments: [
            ("Rire.wav", "Rire.wav"),
            ("a/b.wav", "a-b.wav"),
            ("..wav", "wav"),
            (".caché.mp3", "caché.mp3"),
            ("deux:points.aif", "deux-points.aif"),
            ("", "son"),
        ])
    func sanitize(input: String, expected: String) {
        let name = AudioClip.safeFileName(from: input)
        #expect(name == expected)
        #expect(AudioClip.isSafeFileName(name))
    }

    @Test("Un nom déjà pris reçoit un numéro")
    func unique() {
        let taken: Set<String> = ["rire.wav", "rire 2.wav"]
        #expect(AudioClip.uniqueFileName("rire.wav", avoiding: taken) == "rire 3.wav")
        #expect(AudioClip.uniqueFileName("porte.wav", avoiding: taken) == "porte.wav")
        #expect(AudioClip.uniqueFileName("sans extension", avoiding: ["sans extension"]) == "sans extension 2")
    }

    @Test("Un nom trop long est raccourci en gardant l'extension")
    func longName() {
        let name = AudioClip.safeFileName(from: String(repeating: "a", count: 400) + ".wav")
        #expect(name.count <= 255)
        #expect(name.hasSuffix(".wav"))
    }
}
