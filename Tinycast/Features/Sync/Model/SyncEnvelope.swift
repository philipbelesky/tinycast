import CryptoKit
import Foundation

/// The one value Tinycast stores in iCloud key-value storage: a backup plus display metadata.
struct SyncEnvelope: Codable {
    var writtenAt: Date // display metadata only; ordering is KVS last-writer-wins, never this clock
    var writtenBy: String
    var backup: SettingsBackup
}

// MARK: - Canonical serialization (compact and key-sorted, so equal content means equal bytes)

extension SyncEnvelope {
    private static var canonicalEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func encoded() throws -> Data {
        try Self.canonicalEncoder.encode(self)
    }

    init(json: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self = try decoder.decode(SyncEnvelope.self, from: json)
    }

    /// SHA-256 of the backup alone: metadata must never make two identical configurations differ.
    static func contentHash(of backup: SettingsBackup) throws -> String {
        SHA256.hash(data: try canonicalEncoder.encode(backup))
            .map { String(format: "%02x", $0) }.joined()
    }
}
