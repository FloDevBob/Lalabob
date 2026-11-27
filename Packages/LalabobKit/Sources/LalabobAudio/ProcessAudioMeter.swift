import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Mesure le niveau du son d'une autre app (Apple Music) par la capture audio de macOS (« process tap », macOS 14.2+),
/// pour le vumètre des colonnes Music. **Prototype** (spec « Grilles Apple Music », étape 5) :
///
/// - le son de l'app n'est **ni coupé ni modifié** (`CATapUnmuted`) : on ne fait que l'écouter ;
/// - macOS demande l'autorisation « enregistrement audio » la première fois ; refusée, `start` échoue et la carte reste
///   condamnée ;
/// - sur le fil audio : crête du bloc (`vDSP_maxmgv`) écrite dans `ColumnMeters` (atomique), sans verrou ni allocation.
///
/// Non vérifié sur un vrai Mac : la capture d'un morceau protégé (DRM) peut donner du silence.
public actor ProcessAudioMeter {
    /// Crêtes gauche / droite du son capté (colonne 0 de `ColumnMeters`).
    public nonisolated let meters = ColumnMeters(columns: 1)

    public enum Failure: Error, Equatable, Sendable {
        case processNotFound
        case tapRefused(OSStatus)
        case deviceFailed(OSStatus)
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    public init() {}

    public var isRunning: Bool { procID != nil }

    /// Commence à mesurer le son de l'app de ce numéro de processus. Sans effet si une mesure tourne déjà.
    public func start(pid: pid_t) throws(Failure) {
        guard procID == nil else { return }
        let process = try Self.processObject(for: pid)

        let description = CATapDescription(stereoMixdownOfProcesses: [process])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        var tap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        guard tapStatus == noErr else { throw .tapRefused(tapStatus) }
        tapID = tap

        var aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Lalabob · mesure d'Apple Music",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        if let output = Self.defaultOutputUID() {
            aggregateDescription[kAudioAggregateDeviceMainSubDeviceKey] = output
            aggregateDescription[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: output]]
        }
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
        guard aggregateStatus == noErr else {
            stop()
            throw .deviceFailed(aggregateStatus)
        }
        aggregateID = aggregate

        let meters = self.meters
        var proc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, input, _, _, _ in
            // Fil audio : lecture seule, aucun verrou, aucune allocation.
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            var peaks: (Float, Float) = (0, 0)
            for (index, buffer) in buffers.enumerated() {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let channels = Int(max(buffer.mNumberChannels, 1))
                let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
                guard frames > 0 else { continue }
                for channel in 0..<min(channels, 2) {
                    var peak: Float = 0
                    vDSP_maxmgv(data + channel, vDSP_Stride(channels), &peak, vDSP_Length(frames))
                    // Entrelacé : canal 0 / 1 du même tampon ; non entrelacé : un tampon par canal.
                    let target = channels > 1 ? channel : index
                    if target == 0 { peaks.0 = max(peaks.0, peak) } else { peaks.1 = max(peaks.1, peak) }
                }
            }
            meters.record(column: 0, channel: 0, peak: peaks.0)
            meters.record(column: 0, channel: 1, peak: buffers.count == 1 && buffers[0].mNumberChannels == 1 ? peaks.0 : peaks.1)
        }
        guard procStatus == noErr, let proc else {
            stop()
            throw .deviceFailed(procStatus)
        }
        procID = proc
        let startStatus = AudioDeviceStart(aggregate, proc)
        guard startStatus == noErr else {
            stop()
            throw .deviceFailed(startStatus)
        }
    }

    /// Arrête la mesure et défait tout (crêtes remises à zéro). Sans effet sur le son de l'app mesurée.
    public func stop() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        meters.record(column: 0, channel: 0, peak: 0)
        meters.record(column: 0, channel: 1, peak: 0)
    }

    private static func processObject(for pid: pid_t) throws(Failure) -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        guard status == noErr, object != kAudioObjectUnknown else { throw .processNotFound }
        return object
    }

    private static func defaultOutputUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else {
            return nil
        }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
}
