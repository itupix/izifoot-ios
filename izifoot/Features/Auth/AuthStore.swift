import Combine
import Foundation

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var me: Me?
    @Published private(set) var isRestoringSession = false
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    private let api: IzifootAPI
    private let tokenStore: TokenStoreProtocol
    private var cancellables = Set<AnyCancellable>()

    init(api: IzifootAPI = IzifootAPI(), tokenStore: TokenStoreProtocol = TokenStore.shared) {
        self.api = api
        self.tokenStore = tokenStore
        self.me = tokenStore.cachedMe
        subscribeToSessionExpiry()
    }

    var isLoading: Bool { isRestoringSession || isAuthenticating }
    var isAuthenticated: Bool { me != nil }

    func restoreSessionIfPossible() async {
        guard tokenStore.token != nil else { return }
        isRestoringSession = true
        defer { isRestoringSession = false }

        if me == nil {
            me = tokenStore.cachedMe
        }

        do {
            let refreshedMe = try await api.me()
            me = refreshedMe
            tokenStore.cachedMe = refreshedMe
        } catch {
            if case APIError.unauthorized = error {
                clearSession()
            }
        }
    }

    func login(email: String, password: String) async {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            let response = try await api.login(email: email, password: password)
            if let token = response.token {
                tokenStore.token = token
            }
            if let normalizedMe = response.normalizedMe {
                me = normalizedMe
                tokenStore.cachedMe = normalizedMe
            }
            let refreshedMe = try await api.me()
            me = refreshedMe
            tokenStore.cachedMe = refreshedMe
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func register(email: String, password: String, clubName: String) async {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            let response = try await api.register(email: email, password: password, clubName: clubName)
            if let token = response.token {
                tokenStore.token = token
            }
            if let normalizedMe = response.normalizedMe {
                me = normalizedMe
                tokenStore.cachedMe = normalizedMe
            }
            let refreshedMe = try await api.me()
            me = refreshedMe
            tokenStore.cachedMe = refreshedMe
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func refreshMe() async {
        guard tokenStore.token != nil else { return }
        do {
            let refreshedMe = try await api.me()
            me = refreshedMe
            tokenStore.cachedMe = refreshedMe
        } catch {
            if case APIError.unauthorized = error {
                clearSession()
            } else {
                if !error.isCancellationError { errorMessage = error.localizedDescription }
            }
        }
    }

    func logout() async {
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await api.logout()
        } catch {
            // Keep logout resilient even if backend call fails.
        }

        clearSession()
    }

    private func subscribeToSessionExpiry() {
        NotificationCenter.default.publisher(for: .sessionDidExpire)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clearSession()
            }
            .store(in: &cancellables)
    }

    private func clearSession() {
        tokenStore.token = nil
        tokenStore.cachedMe = nil
        AppSession.shared.activeTeamID = nil
        me = nil
    }
}
