import Foundation
import CryptoKit
import Security

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 60 }
}
struct AuthUser: Codable, Equatable {
    let id: UUID
    let email: String
}

enum KeychainSessionStore {
    private static let service = "com.juliosuas.rocio.auth"
    private static let account = "supabase-session"

    static func load() -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func save(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw BackendError.invalidResponse
            }
        } else if status != errSecSuccess {
            throw BackendError.invalidResponse
        }
    }

    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}

struct PasswordRecoveryPKCE: Equatable {
    let codeVerifier: String
    let codeChallenge: String

    static func generate() throws -> PasswordRecoveryPKCE {
        var randomBytes = [UInt8](repeating: 0, count: 64)
        guard SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess else {
            throw BackendError.invalidResponse
        }
        let verifier = Data(randomBytes).base64URLEncodedString()
        return PasswordRecoveryPKCE(
            codeVerifier: verifier,
            codeChallenge: challenge(for: verifier)
        )
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

enum PasswordRecoveryCodeVerifierStore {
    private static let service = "com.juliosuas.rocio.auth"
    private static let account = "password-recovery-code-verifier"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let verifier = String(data: data, encoding: .utf8),
              !verifier.isEmpty else { return nil }
        return verifier
    }

    static func save(_ verifier: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(verifier.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw BackendError.invalidResponse
            }
        } else if status != errSecSuccess {
            throw BackendError.invalidResponse
        }
    }

    static func clear() throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BackendError.invalidResponse
        }
    }
}

final class PasswordRecoveryCodeVerifierPersistence: @unchecked Sendable {
    private static let consumedVerifierLimit = 64

    private let lock = NSLock()
    private let loadValue: @Sendable () -> String?
    private let saveValue: @Sendable (String) throws -> Void
    private let clearValue: @Sendable () throws -> Void
    private var consumedVerifierDigests: [Data] = []

    init(
        load: @escaping @Sendable () -> String?,
        save: @escaping @Sendable (String) throws -> Void,
        clear: @escaping @Sendable () throws -> Void
    ) {
        loadValue = load
        saveValue = save
        clearValue = clear
    }

    func load() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let verifier = loadValue(), !wasConsumed(verifier) else { return nil }
        return verifier
    }

    @discardableResult
    func replace(_ verifier: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        let previousVerifier = loadValue()
        try saveValue(verifier)
        // A freshly installed request owns this value. A cryptographic
        // collision is implausible, but clearing its old tombstone keeps the
        // state machine correct for injected generators and deterministic tests.
        forgetConsumption(of: verifier)
        return previousVerifier
    }

    func consume(_ verifier: String) {
        lock.lock()
        defer { lock.unlock() }
        recordConsumption(of: verifier)
        guard loadValue() == verifier else { return }
        try? clearValue()
    }

    @discardableResult
    func restorePreviousIfCurrent(
        _ currentVerifier: String,
        _ previousVerifier: String?
    ) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard loadValue() == currentVerifier else { return false }

        let verifierToRestore = previousVerifier.flatMap { wasConsumed($0) ? nil : $0 }
        if let verifierToRestore {
            do {
                try saveValue(verifierToRestore)
            } catch {
                try? clearValue()
                throw error
            }
        } else {
            try clearValue()
        }
        return true
    }

    private func recordConsumption(of verifier: String) {
        let digest = Self.digest(of: verifier)
        consumedVerifierDigests.removeAll { $0 == digest }
        consumedVerifierDigests.append(digest)
        if consumedVerifierDigests.count > Self.consumedVerifierLimit {
            consumedVerifierDigests.removeFirst(
                consumedVerifierDigests.count - Self.consumedVerifierLimit
            )
        }
    }

    private func forgetConsumption(of verifier: String) {
        let digest = Self.digest(of: verifier)
        consumedVerifierDigests.removeAll { $0 == digest }
    }

    private func wasConsumed(_ verifier: String) -> Bool {
        consumedVerifierDigests.contains(Self.digest(of: verifier))
    }

    private static func digest(of verifier: String) -> Data {
        Data(SHA256.hash(data: Data(verifier.utf8)))
    }

    static let keychain = PasswordRecoveryCodeVerifierPersistence(
        load: { PasswordRecoveryCodeVerifierStore.load() },
        save: { try PasswordRecoveryCodeVerifierStore.save($0) },
        clear: { try PasswordRecoveryCodeVerifierStore.clear() }
    )
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
