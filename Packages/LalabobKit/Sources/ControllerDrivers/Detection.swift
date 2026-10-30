import LalabobMIDI

extension ControllerModel {
    /// Reconnaît un contrôleur d'après le nom d'un port MIDI (« Launchpad X LPX MIDI », « APC mini mk2 Control »…).
    /// `nil` si ce n'est aucun des contrôleurs pris en charge.
    public static func detect(portName: String) -> ControllerModel? {
        let name = portName.lowercased()
        if name.contains("apc mini mk2") { return .apcMiniMK2 }
        guard name.contains("launchpad") else { return nil }
        if name.contains("mini mk3") || name.contains("lpminimk3") { return .launchpadMiniMK3 }
        if name.contains("pro mk3") || name.contains("lppromk3") { return .launchpadProMK3 }
        if name.contains("launchpad x") || name.contains("lpx") { return .launchpadX }
        return nil
    }

    /// Un Launchpad expose deux ports (« DAW » et « MIDI ») : Lalabob n'utilise que le port MIDI,
    /// celui du mode Programmeur (voir docs/hardware/launchpad-mk3.md).
    public func isControlPort(named portName: String) -> Bool {
        switch self {
        case .launchpadX, .launchpadMiniMK3, .launchpadProMK3:
            !portName.lowercased().contains("daw")
        case .apcMiniMK2:
            true
        }
    }

    /// Identifiant de fabricant MIDI : Novation `00 20 29`, Akai `47`.
    var manufacturerID: [UInt8] {
        switch self {
        case .launchpadX, .launchpadMiniMK3, .launchpadProMK3: [0x00, 0x20, 0x29]
        case .apcMiniMK2: [0x47]
        }
    }

    /// La réponse à la requête d'identité vient bien du fabricant attendu pour ce modèle.
    /// (Les octets « famille » exacts sont à relever sur le matériel, voir docs/hardware.)
    public func isConsistent(with reply: DeviceInquiry.Reply) -> Bool {
        reply.manufacturer == manufacturerID
    }
}
