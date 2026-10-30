/// Identifiant stable d'un port MIDI (l'identifiant unique CoreMIDI), valable tant que le périphérique existe.
public struct MIDIPortID: Hashable, Sendable {
    public let uniqueID: Int32

    public init(uniqueID: Int32) {
        self.uniqueID = uniqueID
    }
}

/// Un port MIDI du Mac : une source (qui envoie vers nous) ou une destination (où nous envoyons).
public struct MIDIPort: Identifiable, Hashable, Sendable {
    public let id: MIDIPortID
    /// Nom affiché, par exemple « Launchpad X LPX MIDI In ».
    public let name: String
    /// Regroupe la source et la destination d'une même prise du périphérique (0 si inconnu, ports virtuels).
    public let groupID: Int32

    public init(id: MIDIPortID, name: String, groupID: Int32 = 0) {
        self.id = id
        self.name = name
        self.groupID = groupID
    }
}

/// Messages reçus d'une source.
public struct IncomingMIDI: Sendable {
    public let source: MIDIPortID
    public let events: [MIDIEvent]

    public init(source: MIDIPortID, events: [MIDIEvent]) {
        self.source = source
        self.events = events
    }
}

public enum MIDITransportError: Error, Equatable, Sendable {
    case destinationUnavailable
    case sendFailed(Int32)
}

/// Accès au MIDI du Mac. L'implémentation réelle (`CoreMIDISession`) vit dans un acteur ;
/// les tests de l'orchestration utilisent une version factice.
public protocol MIDITransport: Sendable {
    /// Messages reçus des sources écoutées.
    var incoming: AsyncStream<IncomingMIDI> { get }
    /// Émet à chaque branchement, débranchement ou changement de la configuration MIDI.
    var changes: AsyncStream<Void> { get }

    func sources() async -> [MIDIPort]
    func destinations() async -> [MIDIPort]

    /// Commence à recevoir les messages d'une source (sans effet si elle a disparu).
    func listen(to source: MIDIPortID) async
    func stopListening(to source: MIDIPortID) async

    func send(_ events: [MIDIEvent], to destination: MIDIPortID) async throws

    /// Émet des messages sur le port virtuel « Lalabob Lumière » (une source que LightKey écoute).
    func sendLighting(_ events: [MIDIEvent]) async throws
}
