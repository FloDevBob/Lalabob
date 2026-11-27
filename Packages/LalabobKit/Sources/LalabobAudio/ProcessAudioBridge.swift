import AudioToolbox
import CoreAudio
import Foundation

/// Le **pont audio** (ADR 0011) : capte le son d'une autre app (Apple Music) par la capture audio de macOS (« process tap »,
/// macOS 14.2+), **rend l'app muette pendant la capture** (`mutedWhenTapped` : si Lalabob s'arrête, elle redevient audible toute
/// seule) et écrit ce son dans un `AudioRingBuffer`, que le moteur de Lalabob joue dans une colonne.
///
/// Fil de capture : copie dans le tampon, ni verrou ni allocation. macOS demande l'autorisation « enregistrement audio » la première
/// fois ; refusée, `start` échoue. Non vérifié sur un vrai Mac : un morceau protégé (DRM) peut être capté en silence.
public actor ProcessAudioBridge {
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

    /// Capte le son de l'app de ce numéro de processus dans `ring` ; renvoie la fréquence d'échantillonnage du son capté.
    public func start(pid: pid_t, into ring: AudioRingBuffer) throws(Failure) -> Double {
        if procID != nil { stop() }
        let process = try Self.processObject(for: pid)

        let description = CATapDescription(stereoMixdownOfProcesses: [process])
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        var tap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        guard tapStatus == noErr else { throw .tapRefused(tapStatus) }
        tapID = tap
        let sampleRate = Self.sampleRate(ofTap: tap) ?? 48_000

        var aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Lalabob · pont Apple Music",
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

        var proc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, input, _, _, _ in
            // Fil de capture : copie dans le tampon circulaire, aucun verrou, aucune allocation.
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = buffers.first, let firstData = first.mData?.assumingMemoryBound(to: Float.self) else { return }
            if buffers.count >= 2, let secondData = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
                let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
                ring.write(left: firstData, right: secondData, frames: frames)  // non entrelacé : un tampon par canal
            } else {
                let channels = Int(max(first.mNumberChannels, 1))
                let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
                ring.write(left: firstData, right: firstData + (channels > 1 ? 1 : 0), frames: frames, stride: channels)
            }
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
        return sampleRate
    }

    /// Arrête la capture et défait tout : l'app captée redevient audible.
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
    }

    private static func sampleRate(ofTap tap: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr, format.mSampleRate > 0 else { return nil }
        return format.mSampleRate
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
