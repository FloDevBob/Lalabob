import CoreMIDI
import Foundation
import Synchronization

/// Session CoreMIDI de Lalabob : seul endroit de l'app qui parle à CoreMIDI.
///
/// Les callbacks de CoreMIDI arrivent sur un thread à eux : ils se contentent de décoder les paquets
/// et de les déposer dans un `AsyncStream`. Tout le reste passe par l'acteur.
public actor CoreMIDISession: MIDITransport {
    public nonisolated let incoming: AsyncStream<IncomingMIDI>
    public nonisolated let changes: AsyncStream<Void>

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    /// Source virtuelle « Lalabob Lumière » : sortie seule, Lalabob ne l'écoute jamais (pas de boucle).
    private var lightingSource = MIDIEndpointRef()
    private var listening: Set<MIDIPortID> = []

    /// Décodeurs UMP, un par source (un SysEx peut arriver en plusieurs envois).
    private final class Decoders: Sendable {
        let state = Mutex<[Int32: UMPDecoder]>([:])

        func decode(_ words: [UInt32], from source: Int32) -> [MIDIEvent] {
            state.withLock { decoders in
                var decoder = decoders[source] ?? UMPDecoder()
                let events = decoder.decode(words)
                decoders[source] = decoder
                return events
            }
        }

        func forget(_ source: Int32) { state.withLock { _ = $0.removeValue(forKey: source) } }
    }
    private let decoders = Decoders()

    public static let lightingPortName = "Lalabob Lumière"
    private static let lightingIDKey = "lightingPortUniqueID"

    public init(clientName: String = "Lalabob", defaults: UserDefaults = .standard) throws {
        let (incoming, incomingContinuation) = AsyncStream.makeStream(of: IncomingMIDI.self, bufferingPolicy: .unbounded)
        let (changes, changesContinuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        self.incoming = incoming
        self.changes = changes

        var client = MIDIClientRef()
        var status = MIDIClientCreateWithBlock(clientName as CFString, &client) { notification in
            switch notification.pointee.messageID {
            case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved: changesContinuation.yield()
            default: break
            }
        }
        guard status == noErr else { throw MIDITransportError.sendFailed(status) }

        let decoders = self.decoders
        var input = MIDIPortRef()
        status = MIDIInputPortCreateWithProtocol(client, "Entrée" as CFString, ._1_0, &input) { eventList, refCon in
            let source = Int32(truncatingIfNeeded: Int(bitPattern: refCon))
            var words: [UInt32] = []
            for packet in eventList.unsafeSequence() {
                words.append(contentsOf: Self.words(of: packet))
            }
            let events = decoders.decode(words, from: source)
            if !events.isEmpty {
                incomingContinuation.yield(IncomingMIDI(source: MIDIPortID(uniqueID: source), events: events))
            }
        }
        guard status == noErr else { throw MIDITransportError.sendFailed(status) }

        var output = MIDIPortRef()
        status = MIDIOutputPortCreate(client, "Sortie" as CFString, &output)
        guard status == noErr else { throw MIDITransportError.sendFailed(status) }

        // Même identifiant unique qu'au lancement précédent : LightKey retrouve le port sans nouveau réglage.
        var lighting = MIDIEndpointRef()
        status = MIDISourceCreateWithProtocol(client, Self.lightingPortName as CFString, ._1_0, &lighting)
        guard status == noErr else { throw MIDITransportError.sendFailed(status) }
        let savedID = Int32(truncatingIfNeeded: defaults.integer(forKey: Self.lightingIDKey))
        if savedID == 0 || MIDIObjectSetIntegerProperty(lighting, kMIDIPropertyUniqueID, savedID) != noErr {
            var currentID: Int32 = 0
            MIDIObjectGetIntegerProperty(lighting, kMIDIPropertyUniqueID, &currentID)
            defaults.set(Int(currentID), forKey: Self.lightingIDKey)
        }

        self.client = client
        self.inputPort = input
        self.outputPort = output
        self.lightingSource = lighting
    }

    // MARK: - Ports

    public func sources() -> [MIDIPort] {
        (0..<MIDIGetNumberOfSources()).compactMap { Self.port(for: MIDIGetSource($0)) }
    }

    public func destinations() -> [MIDIPort] {
        (0..<MIDIGetNumberOfDestinations()).compactMap { Self.port(for: MIDIGetDestination($0)) }
    }

    public func listen(to source: MIDIPortID) {
        guard !listening.contains(source), let endpoint = Self.endpoint(for: source) else { return }
        let refCon = UnsafeMutableRawPointer(bitPattern: Int(source.uniqueID))
        if MIDIPortConnectSource(inputPort, endpoint, refCon) == noErr { listening.insert(source) }
    }

    public func stopListening(to source: MIDIPortID) {
        guard listening.remove(source) != nil else { return }
        decoders.forget(source.uniqueID)
        if let endpoint = Self.endpoint(for: source) { MIDIPortDisconnectSource(inputPort, endpoint) }
    }

    // MARK: - Envoi

    public func send(_ events: [MIDIEvent], to destination: MIDIPortID) throws {
        guard let endpoint = Self.endpoint(for: destination) else { throw MIDITransportError.destinationUnavailable }
        try Self.forEachEventList(events) { list in MIDISendEventList(outputPort, endpoint, list) }
    }

    public func sendLighting(_ events: [MIDIEvent]) throws {
        try Self.forEachEventList(events) { list in MIDIReceivedEventList(lightingSource, list) }
    }

    /// Range les messages dans des listes UMP et appelle `deliver` pour chacune (une seule le plus souvent).
    private static func forEachEventList(
        _ events: [MIDIEvent], deliver: (UnsafePointer<MIDIEventList>) -> OSStatus
    ) throws {
        let messages = events.flatMap { event -> [[UInt32]] in
            let words = UMP.encode(event)
            let size = UMPDecoder.wordCount(forMessageType: words.first.map { $0 >> 28 } ?? 2)
            return stride(from: 0, to: words.count, by: size).map { Array(words[$0..<min($0 + size, words.count)]) }
        }

        let capacity = 65_536
        let raw = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: MemoryLayout<MIDIEventList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIEventList.self, capacity: 1)

        func flush() throws {
            let status = deliver(list)
            guard status == noErr else { throw MIDITransportError.sendFailed(status) }
        }

        // MIDIEventListAdd ne signale pas le débordement : on tient le compte des octets nous-mêmes.
        // Liste : 8 octets d'en-tête ; paquet : 8 (horodatage) + 4 (nombre de mots) + 4 par mot.
        let listHeader = 8
        var packet = MIDIEventListInit(list, ._1_0)
        var used = listHeader
        for words in messages {
            let needed = 12 + words.count * 4
            if used + needed > capacity, used > listHeader {
                try flush()
                packet = MIDIEventListInit(list, ._1_0)
                used = listHeader
            }
            packet = MIDIEventListAdd(list, capacity, packet, 0, words.count, words)
            used += needed
        }
        if used > listHeader { try flush() }
    }

    // MARK: - CoreMIDI

    /// Les mots d'un paquet. On lit à l'adresse réelle des mots : la liste est plus courte que le type Swift.
    private static func words(of packet: UnsafePointer<MIDIEventPacket>) -> [UInt32] {
        let count = Int(packet.pointee.wordCount)
        guard count > 0, let offset = MemoryLayout<MIDIEventPacket>.offset(of: \.words) else { return [] }
        let start = (UnsafeRawPointer(packet) + offset).assumingMemoryBound(to: UInt32.self)
        return Array(UnsafeBufferPointer(start: start, count: count))
    }

    private static func port(for endpoint: MIDIEndpointRef) -> MIDIPort? {
        var uniqueID: Int32 = 0
        guard MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID) == noErr else { return nil }
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
        var entity = MIDIEntityRef()
        var groupID: Int32 = 0
        if MIDIEndpointGetEntity(endpoint, &entity) == noErr, entity != 0 {
            MIDIObjectGetIntegerProperty(entity, kMIDIPropertyUniqueID, &groupID)
        }
        return MIDIPort(
            id: MIDIPortID(uniqueID: uniqueID),
            name: (name?.takeRetainedValue() as String?) ?? "",
            groupID: groupID
        )
    }

    private static func endpoint(for port: MIDIPortID) -> MIDIEndpointRef? {
        var object = MIDIObjectRef()
        var type = MIDIObjectType.other
        guard MIDIObjectFindByUniqueID(port.uniqueID, &object, &type) == noErr, object != 0 else { return nil }
        switch type {
        case .source, .destination, .externalSource, .externalDestination: return object
        default: return nil
        }
    }
}
