import Foundation
import Security

/// Persists the Mudbase access + refresh token pair (real or anonymous — both are ordinary JWTs
/// with the same refresh contract, see `SessionStore` doc comments) in the iOS/macOS Keychain.
/// Never `UserDefaults` — that is a hard security rule for this project (tokens in `UserDefaults`
/// are readable from an unencrypted plist on jailbroken devices and in local device backups).
/// Ported verbatim from the sibling `mudbase-showcase-ecommerce`/`mudbase-showcase-social` Swift
/// ports' `Support/KeychainTokenStore.swift`.
struct KeychainTokenStore: Sendable {
    struct StoredSession: Sendable, Equatable {
        let accessToken: String
        let refreshToken: String
    }

    private let service: String
    private let accessTokenAccount = "mudbase.accessToken"
    private let refreshTokenAccount = "mudbase.refreshToken"

    init(service: String = "dev.mudbase.showcase.docssearch") {
        self.service = service
    }

    func save(_ session: StoredSession) {
        set(session.accessToken, account: accessTokenAccount)
        set(session.refreshToken, account: refreshTokenAccount)
    }

    func load() -> StoredSession? {
        guard let accessToken = get(account: accessTokenAccount),
              let refreshToken = get(account: refreshTokenAccount)
        else {
            return nil
        }
        return StoredSession(accessToken: accessToken, refreshToken: refreshToken)
    }

    func clear() {
        delete(account: accessTokenAccount)
        delete(account: refreshTokenAccount)
    }

    private func set(_ value: String, account: String) {
        delete(account: account)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    private func get(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(account: String) {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
