import Foundation

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var me: Me?
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    private let api: IzifootAPI
    private let tokenStore: TokenStoreProtocol

    init(api: IzifootAPI = IzifootAPI(), tokenStore: TokenStoreProtocol = TokenStore.shared) {
        self.api = api
        self.tokenStore = tokenStore
    }

    var isAuthenticated: Bool { me != nil }

    func restoreSessionIfPossible() async {
        guard tokenStore.token != nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            me = try await api.me()
        } catch {
            tokenStore.token = nil
            me = nil
        }
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await api.login(email: email, password: password)
            if let token = response.token {
                tokenStore.token = token
            }
            if let normalizedMe = response.normalizedMe {
                me = normalizedMe
            } else {
                me = try await api.me()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func register(email: String, password: String, clubName: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await api.register(email: email, password: password, clubName: clubName)
            if let token = response.token {
                tokenStore.token = token
            }
            if let normalizedMe = response.normalizedMe {
                me = normalizedMe
            } else {
                me = try await api.me()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshMe() async {
        guard tokenStore.token != nil else { return }
        do {
            me = try await api.me()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await api.logout()
        } catch {
            // Keep logout resilient even if backend call fails.
        }

        tokenStore.token = nil
        me = nil
    }
}
