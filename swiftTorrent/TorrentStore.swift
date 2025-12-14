//
//  TorrentStore.swift
//  swiftTorrent
//
//  Created by Max Hewett on 14/12/2025.
//

import Foundation

struct StoredTorrent: Codable, Hashable {
    /// Stable key derived from magnet: btih hex (40) or btmh sha256 hex (64) when available.
    let key: String
    let magnet: String
    let savePath: String
    var category: String?
}

enum TorrentStore {
    static let fileName = "torrents.json"

    static func load() -> [StoredTorrent] {
        let url = storeURL()
        guard let data = try? Data(contentsOf: url) else { return [] }

        // Current format
        if let decoded = try? JSONDecoder().decode([StoredTorrent].self, from: data) {
            return decoded
        }

        // Backward compatibility: previous "category but no key" format
        struct LegacyCategory: Codable {
            let magnet: String
            let savePath: String
            let category: String?
        }
        if let legacy = try? JSONDecoder().decode([LegacyCategory].self, from: data) {
            return legacy.map {
                StoredTorrent(
                    key: MagnetKeyExtractor.key(from: $0.magnet) ?? $0.magnet,
                    magnet: $0.magnet,
                    savePath: $0.savePath,
                    category: $0.category
                )
            }
        }

        // Backward compatibility: old "tags" format
        struct TagTorrent: Codable {
            let magnet: String
            let savePath: String
            let tags: Set<String>
        }
        if let tagged = try? JSONDecoder().decode([TagTorrent].self, from: data) {
            return tagged.map {
                StoredTorrent(
                    key: MagnetKeyExtractor.key(from: $0.magnet) ?? $0.magnet,
                    magnet: $0.magnet,
                    savePath: $0.savePath,
                    category: $0.tags.sorted().first
                )
            }
        }

        // Oldest format: no category/tags
        struct Legacy: Codable {
            let magnet: String
            let savePath: String
        }
        if let legacy = try? JSONDecoder().decode([Legacy].self, from: data) {
            return legacy.map {
                StoredTorrent(
                    key: MagnetKeyExtractor.key(from: $0.magnet) ?? $0.magnet,
                    magnet: $0.magnet,
                    savePath: $0.savePath,
                    category: nil
                )
            }
        }

        return []
    }

    static func save(_ items: [StoredTorrent]) {
        let url = storeURL()
        do {
            let data = try JSONEncoder().encode(items)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            print("TorrentStore save failed:", error)
        }
    }

    static func storeURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("swiftTorrent", isDirectory: true)
        return dir.appendingPathComponent(fileName)
    }
}

/// Extracts a stable torrent key from a magnet:
/// - btih: 20-byte SHA1 → 40 hex (may be base32 in magnet)
/// - btmh: multihash sha256 often "1220" + 32 bytes → 64 hex
enum MagnetKeyExtractor {

    static func key(from magnet: String) -> String? {
        guard let comps = URLComponents(string: magnet),
              let items = comps.queryItems
        else { return nil }

        // magnets can have multiple xt params
        let xts = items.filter { $0.name == "xt" }.compactMap { $0.value }

        for xt in xts {
            if let k = parseBTIH(xt) { return k }
            if let k = parseBTMH(xt) { return k }
        }
        return nil
    }

    private static func parseBTIH(_ xt: String) -> String? {
        let prefix = "urn:btih:"
        guard xt.lowercased().hasPrefix(prefix) else { return nil }
        let raw = String(xt.dropFirst(prefix.count))

        // If already 40 hex chars
        if raw.count == 40, raw.allHex {
            return raw.lowercased()
        }

        // Otherwise assume base32-encoded btih (common)
        if let data = base32Decode(raw), data.count == 20 {
            return data.hexString
        }

        return nil
    }

    private static func parseBTMH(_ xt: String) -> String? {
        let prefix = "urn:btmh:"
        guard xt.lowercased().hasPrefix(prefix) else { return nil }
        let raw = String(xt.dropFirst(prefix.count))

        // Common format: "1220" + 64 hex (sha256 multihash)
        if raw.lowercased().hasPrefix("1220") {
            let rest = String(raw.dropFirst(4))
            if rest.count == 64, rest.allHex {
                return rest.lowercased()
            }
        }

        // (Some magnets may use base32 here, but we’ll add that later if needed.)
        return nil
    }

    // MARK: base32 (RFC 4648, no padding required)

    private static func base32Decode(_ input: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var table: [Character: UInt8] = [:]
        for (i, c) in alphabet.enumerated() { table[c] = UInt8(i) }

        let cleaned = input
            .uppercased()
            .filter { $0 != "=" && $0 != " " && $0 != "\n" && $0 != "\t" }

        var bits: UInt64 = 0
        var bitCount: Int = 0
        var out = Data()

        for ch in cleaned {
            guard let v = table[ch] else { return nil }
            bits = (bits << 5) | UInt64(v)
            bitCount += 5

            while bitCount >= 8 {
                let shift = bitCount - 8
                let byte = UInt8((bits >> shift) & 0xFF)
                out.append(byte)
                bitCount -= 8
                bits &= (1 << bitCount) - 1
            }
        }

        return out
    }
}

private extension String {
    var allHex: Bool {
        !isEmpty && allSatisfy { $0.isHexDigit }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
