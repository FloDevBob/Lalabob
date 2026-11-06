import Foundation

/// Décompression gzip (RFC 1952). Un `.als` est du XML compressé en gzip.
enum Gzip {
    /// - Parameter maximumSize: taille maximale du résultat. La taille annoncée en pied de fichier est contrôlée
    ///   avant de décompresser, le résultat l'est encore après (le pied peut mentir).
    static func inflate(_ data: Data, maximumSize: Int) throws(AbletonImportError) -> Data {
        let bytes = [UInt8](data)
        // En-tête minimal (10 octets) + pied (8 octets : CRC-32 puis taille d'origine, petit-boutiste).
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B else { throw .notAGzipFile }
        guard bytes[2] == 8 else { throw .corruptArchive }  // 8 = deflate

        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {  // FEXTRA : longueur sur 2 octets puis données
            guard offset + 2 <= bytes.count else { throw .corruptArchive }
            offset += 2 + Int(bytes[offset]) + (Int(bytes[offset + 1]) << 8)
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {  // FNAME, FCOMMENT : texte terminé par un octet nul
            guard offset < bytes.count, let end = bytes[offset...].firstIndex(of: 0) else { throw .corruptArchive }
            offset = end + 1
        }
        if flags & 0x02 != 0 { offset += 2 }  // FHCRC

        let trailer = bytes.count - 8
        guard offset < trailer else { throw .corruptArchive }
        let b0 = Int(bytes[trailer + 4])
        let b1 = Int(bytes[trailer + 5]) << 8
        let b2 = Int(bytes[trailer + 6]) << 16
        let b3 = Int(bytes[trailer + 7]) << 24
        guard b0 | b1 | b2 | b3 <= maximumSize else { throw .tooLarge }

        // `.zlib` de Compression = flux deflate brut (sans l'en-tête zlib), ce qu'il y a entre l'en-tête et le pied gzip.
        let payload = Data(bytes[offset..<trailer])
        let inflated: NSData
        do { inflated = try (payload as NSData).decompressed(using: .zlib) } catch { throw .corruptArchive }
        guard inflated.length <= maximumSize else { throw .tooLarge }
        return inflated as Data
    }
}
