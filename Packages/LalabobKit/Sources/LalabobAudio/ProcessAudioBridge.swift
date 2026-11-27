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

    /// Ce que la capture a trouvé en démarrant (diagnostic affiché dans le panneau).
    public struct Info: Equatable, Sendable {
        /// Fréquence à laquelle l'appareil de capture tourne vraiment : celle des échantillons écrits dans le tampon.
        public var sampleRate: Double
        /// Fréquence annoncée par la capture elle-même.
        public var tapSampleRate: Double
        /// Tampons d'entrée de la sortie audio (micro, entrées de la carte son) sautés avant ceux de la capture.
        public var skippedBuffers: Int

        public init(sampleRate: Double, tapSampleRate: Double, skippedBuffers: Int) {
            self.sampleRate = sampleRate
            self.tapSampleRate = tapSampleRate
            self.skippedBuffers = skippedBuffers
        }
    }

    public init() {}

    public var isRunning: Bool { procID != nil }

    /// Capte le son de l'app de ce numéro de processus dans `ring`. `outputUID` : la sortie où Lalabob joue (`nil` = sortie par
    /// défaut) : la capture suit **son horloge**, avec la compensation de dérive de macOS, pour que capture et lecture avancent au
    /// même pas (sinon le tampon se vide ou déborde : grésillement).
    public func start(pid: pid_t, outputUID: String?, into ring: AudioRingBuffer) throws(Failure) -> Info {
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
        let tapSampleRate = Self.sampleRate(ofTap: tap) ?? 48_000
        let clockUID = outputUID ?? Self.defaultOutputUID()

        var aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Lalabob · pont Apple Music",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        if let output = clockUID {
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
        // La vraie fréquence de l'agrégat (celle de la sortie qui donne l'horloge), et les entrées de cette sortie, qui arrivent
        // avant le son capté dans la liste de tampons.
        let sampleRate = Self.nominalSampleRate(of: aggregate) ?? tapSampleRate
        let skip = clockUID.flatMap(Self.deviceID(forUID:)).map(Self.inputBufferCount(of:)) ?? 0

        var proc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, input, _, _, _ in
            // Fil de capture : copie dans le tampon circulaire, aucun verrou, aucune allocation.
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard buffers.count > skip, let firstData = buffers[skip].mData?.assumingMemoryBound(to: Float.self) else { return }
            let first = buffers[skip]
            if buffers.count >= skip + 2, first.mNumberChannels == 1,
                let secondData = buffers[skip + 1].mData?.assumingMemoryBound(to: Float.self)
            {
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
        return Info(sampleRate: sampleRate, tapSampleRate: tapSampleRate, skippedBuffers: skip)
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

    private static func nominalSampleRate(of device: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr, rate > 0 else { return nil }
        return rate
    }

    private static func deviceID(forUID uid: String) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfUID = uid as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), pointer, &size, &device)
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    /// Nombre de tampons d'entrée d'un appareil (0 pour une sortie sans entrée).
    private static func inputBufferCount(of device: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        return Int(raw.assumingMemoryBound(to: AudioBufferList.self).pointee.mNumberBuffers)
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
