import CoreAudio
import Foundation

/// Une sortie audio branchée (carte son, casque, AirPlay…).
public struct AudioOutputDevice: Identifiable, Hashable, Sendable {
    /// Identifiant stable entre deux branchements (UID CoreAudio).
    public let uid: String
    public let name: String
    public var id: String { uid }

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

/// Liste des sorties audio du Mac et surveillance des branchements.
public enum AudioOutputDevices {
    public static func available() -> [AudioOutputDevice] {
        deviceIDs().compactMap { id in
            guard outputChannelCount(of: id) > 0,
                let uid = string(kAudioDevicePropertyDeviceUID, of: id),
                let name = string(kAudioObjectPropertyName, of: id)
            else { return nil }
            return AudioOutputDevice(uid: uid, name: name)
        }
    }

    /// Émet à chaque branchement ou débranchement d'un périphérique audio.
    public static func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let queue = DispatchQueue(label: "lalabob.audio.device-changes")
            let listener: @Sendable (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void = { _, _ in continuation.yield() }
            var address = propertyAddress(kAudioHardwarePropertyDevices)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
            continuation.onTermination = { _ in
                var address = propertyAddress(kAudioHardwarePropertyDevices)
                AudioObjectRemovePropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
            }
        }
    }

    // MARK: - Utilisé par le moteur

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        deviceIDs().first { string(kAudioDevicePropertyDeviceUID, of: $0) == uid && outputChannelCount(of: $0) > 0 }
    }

    static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    // MARK: - CoreAudio

    private static func propertyAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = propertyAddress(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func outputChannelCount(of device: AudioDeviceID) -> Int {
        var address = propertyAddress(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = propertyAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
