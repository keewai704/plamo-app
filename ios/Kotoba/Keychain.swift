import Foundation
import Security

enum Keychain {
    private static let baseQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "jp.keewai.kotoba",
        kSecAttrAccount as String: "apiKey",
    ]

    static var apiKey: String {
        get {
            var query = baseQuery
            query[kSecReturnData as String] = true
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
                return ""
            }
            return String(decoding: data, as: UTF8.self)
        }
        set {
            SecItemDelete(baseQuery as CFDictionary)
            guard !newValue.isEmpty else { return }
            var query = baseQuery
            query[kSecValueData as String] = Data(newValue.utf8)
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }
}
