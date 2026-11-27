import Testing

@testable import LalabobDMX

@Suite("Détection des boîtiers USB-DMX")
struct DMXPortDiscoveryTests {
    @Test("Seuls les ports série « cu » des puces USB courantes sont retenus, triés")
    func candidates() {
        let names = [
            "tty.usbserial-AU0483EN", "cu.Bluetooth-Incoming-Port", "cu.usbserial-AU0483EN", "cu.debug-console",
            "cu.wchusbserial1410", "cu.SLAB_USBtoUART", "null", "cu.usbmodem1101",
        ]
        let ports = DMXPortDiscovery.candidates(deviceNames: names)
        #expect(ports.map(\.path) == ["/dev/cu.SLAB_USBtoUART", "/dev/cu.usbserial-AU0483EN", "/dev/cu.wchusbserial1410"])
    }

    @Test("Le numéro de série du boîtier FTDI de la troupe se lit dans le nom du port")
    func serialNumber() {
        #expect(DMXPortInfo.troupe.serialNumber == "AU0483EN")
        #expect(DMXPortInfo.troupe.name == "Boîtier USB-DMX AU0483EN")
        #expect(DMXPortInfo(path: "/dev/cu.wchusbserial1410").serialNumber == "1410")
        #expect(DMXPortInfo(path: "/dev/cu.SLAB_USBtoUART").serialNumber == "")
        #expect(DMXPortInfo(path: "/dev/cu.SLAB_USBtoUART").name == "Boîtier USB-DMX")
    }

    @Test("Le boîtier choisi sur ce Mac passe en premier ; absent, on prend le premier branché")
    func choose() {
        let ports = [DMXPortInfo.troupe, .spare]
        #expect(DMXPortDiscovery.choose(from: ports, preferredSerial: "B0001") == .spare)
        #expect(DMXPortDiscovery.choose(from: ports, preferredSerial: "INCONNU") == .troupe)
        #expect(DMXPortDiscovery.choose(from: ports, preferredSerial: nil) == .troupe)
        #expect(DMXPortDiscovery.choose(from: [], preferredSerial: "B0001") == nil)
    }
}
