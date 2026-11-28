import Synchronization

@testable import LalabobDMX

/// Ce que reçoit une fausse ligne série, dans l'ordre.
enum LineOp: Equatable {
    case breakOn
    case breakOff
    case pause(Duration)
    case write([UInt8])
    case drain
    case close
}

/// Fausse ligne série : note chaque opération ; peut échouer à l'écriture (boîtier débranché).
final class FakeLine: SerialLine {
    let port: DMXPortInfo
    private let state = Mutex<(ops: [LineOp], failsWrites: Bool)>(([], false))

    init(port: DMXPortInfo) { self.port = port }

    var ops: [LineOp] { state.withLock { $0.ops } }
    var writes: [[UInt8]] {
        ops.compactMap { if case .write(let bytes) = $0 { bytes } else { nil } }
    }
    var isClosed: Bool { ops.contains(.close) }

    func failWrites() { state.withLock { $0.failsWrites = true } }
    func record(_ op: LineOp) { state.withLock { $0.ops.append(op) } }

    func setBreak(_ on: Bool) throws { record(on ? .breakOn : .breakOff) }
    func write(_ bytes: [UInt8]) throws {
        let fails = state.withLock { $0.failsWrites }
        if fails { throw DMXError.writeFailed(code: 6, message: "Device not configured") }
        record(.write(bytes))
    }
    func drain() throws { record(.drain) }
    func close() { record(.close) }
}

/// Faux accès aux ports : la liste des boîtiers branchés se change à la main.
final class FakeOpener: SerialLineOpener {
    private struct State {
        var ports: [DMXPortInfo] = []
        var refusesOpening = false
        var listings = 0
        var lines: [FakeLine] = []
    }
    private let state = Mutex(State())

    init(ports: [DMXPortInfo] = []) { state.withLock { $0.ports = ports } }

    func plug(_ ports: [DMXPortInfo]) { state.withLock { $0.ports = ports } }
    func refuseOpening(_ refuses: Bool) { state.withLock { $0.refusesOpening = refuses } }
    var listings: Int { state.withLock { $0.listings } }
    var lines: [FakeLine] { state.withLock { $0.lines } }

    func availablePorts() -> [DMXPortInfo] {
        state.withLock {
            $0.listings += 1
            return $0.ports
        }
    }

    func open(_ port: DMXPortInfo) throws -> any SerialLine {
        try state.withLock {
            if $0.refusesOpening { throw DMXError.openFailed(code: 16, message: "Resource busy") }
            let line = FakeLine(port: port)
            $0.lines.append(line)
            return line
        }
    }
}

extension DMXPortInfo {
    static let troupe = DMXPortInfo(path: "/dev/cu.usbserial-AU0483EN")
    static let spare = DMXPortInfo(path: "/dev/cu.usbserial-B0001")
}

/// Écriture Open DMX sans attente réelle.
let instantWriter = OpenDMXWriter(pause: { _ in })
