import Foundation
import Security

/// Pairing survives Tinycast restarts, but never travels in settings or listening history.
struct MusicPairingStore {
    private let keychain = KeychainSecretStore(scope: "music-remote")
    private let account = UUID(uuidString: "E271850C-02D5-40CB-B50F-91E249F17B19")!

    func token() throws -> String {
        if let existing = try keychain.secret(for: account), existing.utf8.allSatisfy({ $0 < 128 }),
            existing.utf8.count >= 24 {
            return existing
        }
        return try rotate()
    }

    func rotate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw MusicAutomationFailure("A pairing token could not be generated.")
        }
        let token = Data(bytes).base64EncodedString()
        try keychain.setSecret(token, for: account)
        return token
    }
}
