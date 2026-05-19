import Foundation
import Security

protocol TokenStoreProtocol: AnyObject {
    var token: String? { get set }
    var refreshToken: String? { get set }
    var cachedMe: Me? { get set }
}

final class TokenStore: TokenStoreProtocol {
    static let shared = TokenStore()

    private let accessTokenKey = "izifoot.auth.token"
    private let refreshTokenKey = "izifoot.auth.refresh-token"
    private let meKey = "izifoot.auth.me"

    var cachedMe: Me? {
        get {
            guard let data = UserDefaults.standard.data(forKey: meKey) else { return nil }
            return try? JSONDecoder().decode(Me.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: meKey)
            } else {
                UserDefaults.standard.removeObject(forKey: meKey)
            }
        }
    }

    var token: String? {
        get {
            if let item = readKeychainValue(for: accessTokenKey) {
                return item
            }

            // Migrate legacy token storage from UserDefaults if present.
            if let legacy = UserDefaults.standard.string(forKey: accessTokenKey), !legacy.isEmpty {
                writeKeychainValue(legacy, for: accessTokenKey)
                UserDefaults.standard.removeObject(forKey: accessTokenKey)
                return legacy
            }

            return nil
        }
        set {
            if let value = newValue, !value.isEmpty {
                writeKeychainValue(value, for: accessTokenKey)
            } else {
                deleteKeychainValue(for: accessTokenKey)
            }
        }
    }

    var refreshToken: String? {
        get {
            readKeychainValue(for: refreshTokenKey)
        }
        set {
            if let value = newValue, !value.isEmpty {
                writeKeychainValue(value, for: refreshTokenKey)
            } else {
                deleteKeychainValue(for: refreshTokenKey)
            }
        }
    }

    private func readKeychainValue(for service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeKeychainValue(_ value: String, for service: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func deleteKeychainValue(for service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
