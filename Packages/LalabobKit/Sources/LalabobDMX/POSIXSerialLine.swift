import Darwin
import Foundation

// Constantes de <sys/ioctl.h> et <IOKit/serial/ioss.h> (macros non importées en Swift).
private let IOSSIOSPEED: UInt = 0x8008_5402  // _IOW('T', 2, speed_t)
private let TIOCSBRK: UInt = 0x2000_747B  // _IO('t', 123) : début du break
private let TIOCCBRK: UInt = 0x2000_747A  // _IO('t', 122) : fin du break
private let TIOCEXCL: UInt = 0x2000_740D  // _IO('t', 13) : accès exclusif

private func systemMessage(_ code: Int32) -> String { String(cString: strerror(code)) }

/// Port série réel (pilote FTDI intégré à macOS). Réglages repris du banc d'essai `tools/banc-dmx`, essayé sur le
/// boîtier de la troupe le 27/11/2026.
public struct POSIXSerialLine: SerialLine {
    let fd: Int32

    public func setBreak(_ on: Bool) throws {
        guard ioctl(fd, on ? TIOCSBRK : TIOCCBRK) == 0 else {
            throw DMXError.breakFailed(code: errno, message: systemMessage(errno))
        }
    }

    public func write(_ bytes: [UInt8]) throws {
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + sent, bytes.count - sent) }
            if n < 0 {
                if errno == EINTR { continue }
                throw DMXError.writeFailed(code: errno, message: systemMessage(errno))
            }
            sent += n
        }
    }

    public func drain() throws {
        guard tcdrain(fd) == 0 else { throw DMXError.writeFailed(code: errno, message: systemMessage(errno)) }
    }

    public func close() { _ = Darwin.close(fd) }
}

/// Accès réel aux ports série : liste de `/dev`, ouverture et réglage DMX.
/// En bac à sable, il faut l'autorisation `com.apple.security.device.serial` (`project.yml`).
public struct POSIXSerialOpener: SerialLineOpener {
    public init() {}

    public func availablePorts() -> [DMXPortInfo] {
        DMXPortDiscovery.candidates(deviceNames: (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? [])
    }

    public func open(_ port: DMXPortInfo) throws -> any SerialLine {
        let fd = Darwin.open(port.path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw DMXError.openFailed(code: errno, message: systemMessage(errno)) }
        func fail(_ code: Int32) -> DMXError {
            _ = Darwin.close(fd)
            return .configurationFailed(code: code, message: systemMessage(code))
        }
        _ = ioctl(fd, TIOCEXCL)  // une seule app à la fois sur le boîtier ; sans gravité si refusé
        guard fcntl(fd, F_SETFL, 0) == 0 else { throw fail(errno) }  // retour au mode bloquant
        var t = termios()
        guard tcgetattr(fd, &t) == 0 else { throw fail(errno) }
        cfmakeraw(&t)
        t.c_cflag &= ~tcflag_t(PARENB | CSIZE | CRTSCTS)
        t.c_cflag |= tcflag_t(CS8 | CSTOPB | CLOCAL | CREAD)  // 8 bits, 2 bits d'arrêt, sans parité
        guard tcsetattr(fd, TCSANOW, &t) == 0 else { throw fail(errno) }
        var speed: speed_t = 250_000
        guard ioctl(fd, IOSSIOSPEED, &speed) == 0 else { throw fail(errno) }
        return POSIXSerialLine(fd: fd)
    }
}
