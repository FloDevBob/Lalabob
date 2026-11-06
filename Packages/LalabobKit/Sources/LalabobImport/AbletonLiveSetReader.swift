import Foundation
import LalabobModel

/// Lecture d'un Live Set Ableton (`.als` = XML compressé en gzip).
///
/// Le XML est lu en flux (`XMLParser`) en suivant le chemin des éléments, jamais chargé en arbre : un gros set fait
/// plusieurs dizaines de Mo. Seuls les chemins utiles sont lus ; tout le reste est ignoré.
///
/// La structure attendue (Live 12) :
/// ```
/// Ableton > LiveSet > Tracks > AudioTrack > Name > UserName / EffectiveName
///                                        > DeviceChain > MainSequencer > ClipSlotList > ClipSlot (une par scène)
///                                            > ClipSlot > Value > AudioClip > Name, Loop > LoopOn,
///                                                                 SampleRef > FileRef > RelativePath / Path / Name
///           > Scenes > Scene
/// ```
public enum AbletonLiveSetReader {
    public static let maximumFileSize = 100 * 1024 * 1024
    public static let maximumXMLSize = 256 * 1024 * 1024
    public static let maximumTracks = 256

    public static func read(fileData: Data) throws(AbletonImportError) -> AbletonLiveSet {
        guard fileData.count <= maximumFileSize else { throw .tooLarge }
        let xml = try Gzip.inflate(fileData, maximumSize: maximumXMLSize)
        return try parse(xml: xml)
    }

    public static func parse(xml: Data) throws(AbletonImportError) -> AbletonLiveSet {
        let collector = Collector()
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.delegate = collector
        guard parser.parse() else { throw .unreadableXML }
        guard collector.sawLiveSet else { throw .notALiveSet }
        return collector.result
    }

    private struct TrackBuilder {
        var userName = ""
        var effectiveName = ""
        var clips: [Int: AbletonClip] = [:]
    }

    private struct ClipBuilder {
        var name = ""
        var loops = false
        var relativePath = ""
        var absolutePath = ""
        var legacyName = ""
        var isWarped = false
        var loopStart = 0.0
        var loopEnd: Double?
        var sampleVolume = 1.0
        var frameCount: Double?
        var sampleRate: Double?
        /// (secondes, battements) des marqueurs de warp.
        var warpMarkers: [(seconds: Double, beats: Double)] = []

        func build() -> AbletonClip {
            let fileName = Self.lastComponent(of: absolutePath).nonEmpty
                ?? Self.lastComponent(of: relativePath).nonEmpty ?? legacyName
            let sample: AbletonSampleReference? =
                fileName.isEmpty ? nil : AbletonSampleReference(relativePath: relativePath, absolutePath: absolutePath, fileName: fileName)
            let stem = (fileName as NSString).deletingPathExtension
            var clip = AbletonClip(name: name.isEmpty ? stem : name, loops: loops, sample: sample)
            clip.gainDB = Self.decibels(fromLinear: sampleVolume)
            (clip.trimStart, clip.trimEnd) = trim()
            return clip
        }

        /// Partie jouée, en secondes. Sans durée du fichier ou sans conversion fiable : tout le fichier.
        /// Dans un clip non warpé, les marqueurs sont en secondes ; dans un clip warpé, en battements (conversion par les marqueurs de warp).
        func trim() -> (TimeInterval, TimeInterval?) {
            guard let frames = frameCount, let rate = sampleRate, rate > 0, frames > 0, let end = loopEnd else { return (0, nil) }
            let duration = frames / rate
            var startSeconds = loopStart
            var endSeconds = end
            if isWarped {
                guard let s = Warp.seconds(forBeat: loopStart, markers: warpMarkers),
                    let e = Warp.seconds(forBeat: end, markers: warpMarkers)
                else { return (0, nil) }
                startSeconds = s
                endSeconds = e
            }
            guard startSeconds.isFinite, endSeconds.isFinite else { return (0, nil) }
            let minimum = AudioClip.minimumLength
            let start = min(max(startSeconds, 0), max(duration - minimum, 0))
            let keepsEnd = endSeconds > start + minimum && endSeconds < duration - 0.01
            return (start, keepsEnd ? endSeconds : nil)
        }

        /// Gain linéaire → décibels, borné à la plage de l'inspecteur ; une valeur absurde donne 0 dB.
        static func decibels(fromLinear value: Double) -> Double {
            guard value.isFinite, value > 0 else { return 0 }
            let db = 20 * log10(value)
            return (min(max(db, AudioClip.gainRange.lowerBound), AudioClip.gainRange.upperBound) * 10).rounded() / 10
        }

        static func lastComponent(of path: String) -> String {
            path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        }
    }

    /// Conversion battements → secondes d'après les marqueurs de warp (interpolation linéaire, prolongée au-delà des extrémités).
    enum Warp {
        static func seconds(forBeat beat: Double, markers: [(seconds: Double, beats: Double)]) -> Double? {
            let sorted = markers.sorted { $0.beats < $1.beats }
            guard sorted.count >= 2, beat.isFinite else { return nil }
            // Segment qui contient le battement, ou le premier / dernier segment pour prolonger.
            var index = sorted.count - 2
            for i in 0..<(sorted.count - 1) where beat < sorted[i + 1].beats {
                index = i
                break
            }
            let a = sorted[index], b = sorted[index + 1]
            let span = b.beats - a.beats
            guard span > 0 else { return nil }
            return a.seconds + (beat - a.beats) * (b.seconds - a.seconds) / span
        }
    }

    private final class Collector: NSObject, XMLParserDelegate {
        private static let tracksPath = ["Ableton", "LiveSet", "Tracks"]
        /// Chemins relatifs à une `AudioTrack`.
        private static let slotPath = ["DeviceChain", "MainSequencer", "ClipSlotList", "ClipSlot"]
        private static let clipPath = slotPath + ["ClipSlot", "Value", "AudioClip"]
        /// Profondeur d'un enfant direct d'`AudioTrack` : Ableton, LiveSet, Tracks, AudioTrack.
        private static let trackDepth = 4

        var result = AbletonLiveSet()
        var sawLiveSet = false
        private var path: [String] = []
        private var track: TrackBuilder?
        private var clip: ClipBuilder?
        private var slotIndex = -1

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
        ) {
            path.append(elementName)
            let value = attributeDict["Value"] ?? ""

            if path == ["Ableton"] {
                result.creator = attributeDict["Creator"] ?? ""
            } else if path == ["Ableton", "LiveSet"] {
                sawLiveSet = true
            } else if path == ["Ableton", "LiveSet", "Scenes", "Scene"] {
                result.sceneCount += 1
            } else if path.count == Self.trackDepth, Array(path.prefix(3)) == Self.tracksPath {
                if elementName == "AudioTrack" {
                    track = TrackBuilder()
                    slotIndex = -1
                } else if elementName == "MidiTrack" {
                    result.ignoredMidiTrackCount += 1
                }
            } else if track != nil, path.count > Self.trackDepth {
                let relative = Array(path.dropFirst(Self.trackDepth))
                if clip != nil {
                    switch Array(relative.dropFirst(Self.clipPath.count)) {
                    case ["Name"]: clip?.name = value
                    case ["Loop", "LoopOn"]: clip?.loops = (value == "true")
                    case ["SampleRef", "FileRef", "RelativePath"]: clip?.relativePath = value
                    case ["SampleRef", "FileRef", "Path"]: clip?.absolutePath = value
                    case ["SampleRef", "FileRef", "Name"]: clip?.legacyName = value
                    case ["SampleRef", "DefaultDuration"]: clip?.frameCount = Double(value)
                    case ["SampleRef", "DefaultSampleRate"]: clip?.sampleRate = Double(value)
                    case ["IsWarped"]: clip?.isWarped = (value == "true")
                    case ["Loop", "LoopStart"]: clip?.loopStart = Double(value) ?? 0
                    case ["Loop", "LoopEnd"]: clip?.loopEnd = Double(value)
                    case ["SampleVolume"]: clip?.sampleVolume = Double(value) ?? 1
                    case ["WarpMarkers", "WarpMarker"]:
                        if let seconds = Double(attributeDict["SecTime"] ?? ""), let beats = Double(attributeDict["BeatTime"] ?? "") {
                            clip?.warpMarkers.append((seconds, beats))
                        }
                    default: break
                    }
                } else if relative == ["Name", "UserName"] {
                    track?.userName = value
                } else if relative == ["Name", "EffectiveName"] {
                    track?.effectiveName = value
                } else if relative == Self.slotPath {
                    slotIndex += 1
                } else if relative == Self.clipPath, slotIndex >= 0 {
                    clip = ClipBuilder()
                }
            }
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
        ) {
            defer { path.removeLast() }
            if clip != nil, elementName == "AudioClip", path.count == Self.trackDepth + Self.clipPath.count {
                if let builder = clip, slotIndex >= 0 { track?.clips[slotIndex] = builder.build() }
                clip = nil
            } else if track != nil, elementName == "AudioTrack", path.count == Self.trackDepth {
                if let finished = track, result.audioTracks.count < AbletonLiveSetReader.maximumTracks {
                    let number = result.audioTracks.count + 1
                    let name = finished.userName.nonEmpty ?? finished.effectiveName.nonEmpty ?? "Piste \(number)"
                    result.audioTracks.append(AbletonAudioTrack(name: name, clips: finished.clips))
                }
                track = nil
            }
        }
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
