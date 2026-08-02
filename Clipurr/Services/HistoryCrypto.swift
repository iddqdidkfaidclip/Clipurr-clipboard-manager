import CryptoKit
import Foundation

enum HistoryCryptoError: Error, LocalizedError, Equatable {
    case invalidKey
    case sealingFailed
    case invalidCiphertext
    case invalidUTF8
    case keyFileFailure

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            "Invalid encryption key"
        case .sealingFailed:
            "Could not encrypt data"
        case .invalidCiphertext:
            "Could not decrypt data"
        case .invalidUTF8:
            "Decrypted data is not valid text"
        case .keyFileFailure:
            "Could not read or write the encryption key file"
        }
    }
}

/// AES-GCM helpers. The key is a 32-byte file in Application Support so Sparkle
/// updates never trigger Login Keychain password prompts.
struct HistoryCryptoService: Sendable {
    private let keyProvider: @Sendable () throws -> SymmetricKey

    static let shared = HistoryCryptoService(
        keyProvider: { try HistoryKeyStore.loadOrCreate() }
    )

    /// In-memory key for unit tests (no disk).
    static func ephemeral(_ key: SymmetricKey = SymmetricKey(size: .bits256)) -> HistoryCryptoService {
        HistoryCryptoService(keyProvider: { key })
    }

    init(keyProvider: @escaping @Sendable () throws -> SymmetricKey) {
        self.keyProvider = keyProvider
    }

    func seal(_ plain: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plain, using: keyProvider())
        guard let combined = sealed.combined else {
            throw HistoryCryptoError.sealingFailed
        }
        return combined
    }

    func open(_ combined: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: keyProvider())
    }

    func sealString(_ string: String) throws -> String {
        try seal(Data(string.utf8)).base64EncodedString()
    }

    func openString(_ string: String) throws -> String {
        guard let combined = Data(base64Encoded: string) else {
            throw HistoryCryptoError.invalidCiphertext
        }
        let plain = try open(combined)
        guard let decoded = String(data: plain, encoding: .utf8) else {
            throw HistoryCryptoError.invalidUTF8
        }
        return decoded
    }

    static func deleteStoredKey() {
        HistoryKeyStore.delete()
    }
}

enum HistoryKeyStore {
    private static let fileName = "history-aes-gcm-v1.key"

    private static var fileURL: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return root
            .appendingPathComponent("Clipurr", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func loadOrCreate() throws -> SymmetricKey {
        if let existing = try load() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        try save(key)
        return key
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func load() throws -> SymmetricKey? {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            guard data.count == 32 else {
                throw HistoryCryptoError.invalidKey
            }
            return SymmetricKey(data: data)
        } catch let error as HistoryCryptoError {
            throw error
        } catch {
            throw HistoryCryptoError.keyFileFailure
        }
    }

    private static func save(_ key: SymmetricKey) throws {
        let url = fileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = key.withUnsafeBytes { Data($0) }
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw HistoryCryptoError.keyFileFailure
        }
    }
}
