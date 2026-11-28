// Banc d'essai DMX (J14, étape 0) — outil en ligne de commande, hors de l'app.
//
// Parle à un boîtier USB-DMX « de type Open DMX » (puce FTDI, aucun microprogramme DMX) :
// c'est le Mac qui fabrique le signal. Chaque trame = « break » (≥ 88 µs), « mark » (≥ 8 µs),
// code de départ 0, puis une valeur 0–255 par canal, à 250 kbit/s, 8 bits, 2 bits d'arrêt.
//
// Compiler :  swiftc -O tools/banc-dmx/banc-dmx.swift -o /tmp/banc-dmx
// Exemples (barre Chauvet 4BAR LT BT en 15 canaux, adresse 1) :
//   banc-dmx blanc 5              4 projecteurs en blanc pendant 5 s, puis le signal s'arrête
//   banc-dmx couleur 255 0 0 5    4 projecteurs en rouge
//   banc-dmx chenillard 2         chaque projecteur puis chaque couleur, 2 s chacun (vérifie le tableau)
//   banc-dmx canaux 2=255 4=255 5   canaux bruts (numérotés depuis l'adresse)
//   banc-dmx noir 2               tout à zéro
// Options : --port /dev/cu.usbserial-…  --adresse 1  --hz 30  --noir-a-la-fin
// Sans --noir-a-la-fin, le signal s'arrête net à la fin : c'est voulu, pour voir ce que fait la barre.

import Darwin
import Foundation

// MARK: - Constantes de <sys/ioctl.h> et <IOKit/serial/ioss.h> (macros non importées en Swift)

let IOSSIOSPEED: UInt = 0x8008_5402  // _IOW('T', 2, speed_t)
let TIOCSBRK: UInt = 0x2000_747B  // _IO('t', 123) : début du break
let TIOCCBRK: UInt = 0x2000_747A  // _IO('t', 122) : fin du break

// MARK: - Arguments

struct Options {
    var port: String?
    var address = 1
    var hz = 30.0
    var blackAtEnd = false
    var words: [String] = []
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("banc-dmx : \(message)\n".utf8))
    exit(1)
}

func parse() -> Options {
    var options = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "--port": options.port = args.isEmpty ? nil : args.removeFirst()
        case "--adresse": options.address = Int(args.isEmpty ? "" : args.removeFirst()) ?? 0
        case "--hz": options.hz = Double(args.isEmpty ? "" : args.removeFirst()) ?? 0
        case "--noir-a-la-fin": options.blackAtEnd = true
        default: options.words.append(a)
        }
    }
    guard (1...498).contains(options.address) else { fail("adresse entre 1 et 498") }
    guard (1...44).contains(options.hz) else { fail("--hz entre 1 et 44") }
    return options
}

// MARK: - Port série

func findPort() -> String {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
    guard let name = names.filter({ $0.hasPrefix("cu.usbserial-") }).sorted().first else {
        fail("aucun boîtier USB-DMX (/dev/cu.usbserial-…) : est-il branché ?")
    }
    return "/dev/" + name
}

func openDMX(_ path: String) -> Int32 {
    let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
    guard fd >= 0 else { fail("ouverture de \(path) impossible : \(String(cString: strerror(errno)))") }
    _ = fcntl(fd, F_SETFL, 0)  // retour au mode bloquant
    var t = termios()
    guard tcgetattr(fd, &t) == 0 else { fail("tcgetattr : \(String(cString: strerror(errno)))") }
    cfmakeraw(&t)
    t.c_cflag &= ~tcflag_t(PARENB | CSIZE | CRTSCTS)
    t.c_cflag |= tcflag_t(CS8 | CSTOPB | CLOCAL | CREAD)  // 8 bits, 2 bits d'arrêt, sans parité
    guard tcsetattr(fd, TCSANOW, &t) == 0 else { fail("tcsetattr : \(String(cString: strerror(errno)))") }
    var speed: speed_t = 250_000
    guard ioctl(fd, IOSSIOSPEED, &speed) == 0 else {
        fail("vitesse 250 kbit/s refusée : \(String(cString: strerror(errno)))")
    }
    return fd
}

// MARK: - Envoi

/// Envoie `frame` (canaux 1…n, sans le code de départ) en continu pendant `seconds`.
/// Renvoie les intervalles mesurés entre deux trames (ms).
func send(_ fd: Int32, frame: [UInt8], seconds: Double, hz: Double) -> [Double] {
    let packet = [UInt8(0)] + frame  // code de départ 0 = données de gradateurs
    let period = 1.0 / hz
    let start = Date()
    var next = start
    var last: Date?
    var intervals: [Double] = []
    while Date().timeIntervalSince(start) < seconds {
        let now = Date()
        if let last { intervals.append(now.timeIntervalSince(last) * 1000) }
        last = now
        guard ioctl(fd, TIOCSBRK) == 0 else { fail("break refusé : \(String(cString: strerror(errno)))") }
        usleep(120)  // break ≥ 88 µs
        _ = ioctl(fd, TIOCCBRK)
        usleep(16)  // mark after break ≥ 8 µs
        let written = packet.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == packet.count else { fail("écriture incomplète (\(written) / \(packet.count))") }
        tcdrain(fd)  // attendre que la trame soit partie avant le break suivant
        next += period
        let wait = next.timeIntervalSinceNow
        if wait > 0 { usleep(useconds_t(wait * 1_000_000)) } else { next = Date() }
    }
    return intervals
}

// MARK: - Trames de la barre (15 canaux : programme, gradateur, strobo, puis R V B × 4)

func barFrame(heads: [(UInt8, UInt8, UInt8)], dimmer: UInt8 = 255) -> [UInt8] {
    var f: [UInt8] = [0, dimmer, 0]  // programme 0 = pilotage DMX direct, strobo 0 = aucun
    for h in heads.prefix(4) { f += [h.0, h.1, h.2] }
    while f.count < 15 { f.append(0) }
    return f
}

func placed(_ frame: [UInt8], at address: Int) -> [UInt8] {
    Array(repeating: 0, count: address - 1) + frame
}

func number(_ s: String?, _ what: String) -> Int {
    guard let s, let v = Int(s) else { fail("\(what) attendu") }
    return v
}

func byte(_ s: String?, _ what: String) -> UInt8 {
    let v = number(s, what)
    guard (0...255).contains(v) else { fail("\(what) entre 0 et 255") }
    return UInt8(v)
}

func report(_ label: String, _ intervals: [Double]) {
    guard !intervals.isEmpty else { print("  \(label)"); return }
    let mean = intervals.reduce(0, +) / Double(intervals.count)
    let worst = intervals.max() ?? 0
    print(String(format: "  %@ — %d trames, intervalle moyen %.1f ms, pire %.1f ms", label, intervals.count + 1, mean, worst))
}

// MARK: - Programme

let options = parse()
var words = options.words
guard let command = words.first else {
    print("Usage : banc-dmx blanc|couleur R V B|chenillard|canaux N=V…|noir [secondes] [--port …] [--adresse 1] [--hz 30] [--noir-a-la-fin]")
    exit(0)
}
words.removeFirst()
let path = options.port ?? findPort()
let fd = openDMX(path)
print("Port \(path), adresse \(options.address), \(Int(options.hz)) Hz")

func duration(_ s: String?, default d: Double) -> Double { s.flatMap(Double.init) ?? d }

switch command {
case "blanc":
    let s = duration(words.first, default: 5)
    report("blanc", send(fd, frame: placed(barFrame(heads: Array(repeating: (255, 255, 255), count: 4)), at: options.address), seconds: s, hz: options.hz))
case "couleur":
    let c = (byte(words[safe: 0], "rouge"), byte(words[safe: 1], "vert"), byte(words[safe: 2], "bleu"))
    let s = duration(words[safe: 3], default: 5)
    report("couleur", send(fd, frame: placed(barFrame(heads: Array(repeating: c, count: 4)), at: options.address), seconds: s, hz: options.hz))
case "chenillard":
    let s = duration(words.first, default: 2)
    let colors: [(String, (UInt8, UInt8, UInt8))] = [("rouge", (255, 0, 0)), ("vert", (0, 255, 0)), ("bleu", (0, 0, 255))]
    for head in 0..<4 {
        for (name, c) in colors {
            var heads = Array(repeating: (UInt8(0), UInt8(0), UInt8(0)), count: 4)
            heads[head] = c
            report("projecteur \(head + 1) \(name)", send(fd, frame: placed(barFrame(heads: heads), at: options.address), seconds: s, hz: options.hz))
        }
    }
    report("gradateur général à 25 % (4 en blanc)", send(fd, frame: placed(barFrame(heads: Array(repeating: (255, 255, 255), count: 4), dimmer: 64), at: options.address), seconds: s, hz: options.hz))
case "canaux":
    var frame = [UInt8](repeating: 0, count: 15)
    var s = 5.0
    for w in words {
        if let eq = w.firstIndex(of: "=") {
            let ch = number(String(w[..<eq]), "canal")
            guard (1...512).contains(ch) else { fail("canal entre 1 et 512") }
            if ch > frame.count { frame += [UInt8](repeating: 0, count: ch - frame.count) }
            frame[ch - 1] = byte(String(w[w.index(after: eq)...]), "valeur")
        } else {
            s = duration(w, default: 5)
        }
    }
    report("canaux", send(fd, frame: placed(frame, at: options.address), seconds: s, hz: options.hz))
case "noir":
    let s = duration(words.first, default: 2)
    report("noir", send(fd, frame: placed(barFrame(heads: [], dimmer: 0), at: options.address), seconds: s, hz: options.hz))
default:
    fail("commande inconnue : \(command)")
}

if options.blackAtEnd {
    report("noir de fin", send(fd, frame: placed(barFrame(heads: [], dimmer: 0), at: options.address), seconds: 1, hz: options.hz))
}
close(fd)
print("Signal arrêté.")

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
