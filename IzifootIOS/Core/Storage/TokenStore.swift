import Foundation

protocol TokenStoreProtocol {
    var token: String? { get set }
}

final class TokenStore: TokenStoreProtocol {
    static let shared = TokenStore()

    private let key = "izifoot.auth.token"

    var token: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set {
            if let value = newValue, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
