import Testing

@testable import LalabobModel

@Suite("Réglages d'un extrait")
struct ClipSettingsTests {
    private let clip = AudioClip(fileName: "a.wav")

    @Test func trimIsKeptInsideTheFile() throws {
        let trimmed = clip.trimmed(start: 1, end: 3, fileDuration: 10)
        #expect(trimmed.trimStart == 1)
        #expect(trimmed.trimEnd == 3)
        try Show.validatePad(trimmed)
    }

    @Test func trimEndAtTheEndOfTheFileMeansNoEnd() {
        let trimmed = clip.trimmed(start: 0, end: 10, fileDuration: 10)
        #expect(trimmed.trimEnd == nil)
    }

    @Test func trimHandlesCannotCrossOrLeaveTheFile() throws {
        let trimmed = clip.trimmed(start: 8, end: 2, fileDuration: 10)
        #expect(trimmed.trimStart <= 8)
        let end = try #require(trimmed.trimEnd)
        #expect(end - trimmed.trimStart >= AudioClip.minimumLength - 1e-9)
        let outside = clip.trimmed(start: -4, end: 40, fileDuration: 10)
        #expect(outside.trimStart == 0)
        #expect(outside.trimEnd == nil)
        try Show.validatePad(trimmed)
    }

    @Test func fadesAreClampedAndZeroMeansNoFade() throws {
        #expect(clip.withFades(in: 0, out: 0).fadeIn == nil)
        #expect(clip.withFades(in: 2, out: 3).fadeOut == 3)
        #expect(clip.withFades(in: -1, out: 9999).fadeIn == nil)
        #expect(clip.withFades(in: -1, out: 9999).fadeOut == AudioClip.maximumFade)
        try Show.validatePad(clip.withFades(in: 700, out: 700))
    }

    @Test func gainIsClampedRoundedAndNeverInvalid() throws {
        #expect(clip.withGain(-4).gainDB == -4)
        #expect(clip.withGain(-4.04).gainDB == -4)  // arrondi au dixième
        #expect(clip.withGain(-500).gainDB == AudioClip.gainRange.lowerBound)
        #expect(clip.withGain(500).gainDB == AudioClip.gainRange.upperBound)
        #expect(clip.withGain(.nan).gainDB == 0)
        #expect(clip.withGain(.infinity).gainDB == AudioClip.gainRange.upperBound)
        try Show.validatePad(clip.withGain(-500))
        try Show.validatePad(clip.withGain(500))
    }

    @Test func gainRangeStaysInsideWhatValidationAccepts() {
        #expect(AudioClip.gainRange.lowerBound >= -60)
        #expect(AudioClip.gainRange.upperBound <= 24)
    }
}
