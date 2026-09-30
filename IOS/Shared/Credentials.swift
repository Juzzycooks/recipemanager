import Foundation
import Security

/// Where the app is signed in and its API token. One Keychain item holds both, so the Share extension (which
/// lists the same keychain access group in its entitlements) reads exactly what the app wrote.
struct Credentials: Codable, Sendable, Equatable {
    let server: String
    let token: String
}

enum CredentialStore {
    private static let service = "com.justinrahme.RecipeManager.credentials"

    static func read() -> Credentials? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    @discardableResult
    static func write(_ credentials: Credentials) -> Bool {
        delete()
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        var query = base
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete() { SecItemDelete(base as CFDictionary) }

    // No explicit access group: items go to the first group in the target's entitlements, which is the shared one.
    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "credentials"]
    }
}
