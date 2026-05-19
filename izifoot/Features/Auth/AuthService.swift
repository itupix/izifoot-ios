import AuthenticationServices
import Foundation
import UIKit

enum AuthServiceError: LocalizedError {
    case userCancelled
    case invalidStartURL
    case invalidCallback
    case missingCode
    case missingState
    case networkUnavailable
    case exchangeRejected(String)
    case invalidToken

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return nil
        case .invalidStartURL:
            return "L’URL de connexion izifoot est invalide."
        case .invalidCallback:
            return "Le retour depuis izifoot.fr est invalide."
        case .missingCode:
            return "Le code de connexion est manquant."
        case .missingState:
            return "Le state de sécurité est manquant."
        case .networkUnavailable:
            return "Le réseau est indisponible. Réessayez."
        case .exchangeRejected(let message):
            return message
        case .invalidToken:
            return "La connexion a échoué après l’échange du code. Réessayez."
        }
    }
}

@MainActor
final class AuthService: NSObject {
    private let api: IzifootAPI
    private let client: APIClientProtocol
    private let tokenStore: TokenStoreProtocol
    private var webAuthenticationSession: ASWebAuthenticationSession?

    private struct MobileAuthExchangePayload: Encodable {
        let code: String
        let state: String
    }

    private struct MobileAuthExchangeResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let user: Me?
    }

    init(
        api: IzifootAPI = IzifootAPI(),
        client: APIClientProtocol = APIClient.shared,
        tokenStore: TokenStoreProtocol = TokenStore.shared
    ) {
        self.api = api
        self.client = client
        self.tokenStore = tokenStore
        super.init()
    }

    func signInWithWeb() async throws -> Me {
        let callbackURL = try await authenticateOnWeb()
        let (code, state) = try parseCallback(callbackURL)

        do {
            let response = try await client.post(
                "/auth/mobile/exchange",
                body: MobileAuthExchangePayload(code: code, state: state),
                responseType: MobileAuthExchangeResponse.self
            )
            tokenStore.token = response.accessToken
            tokenStore.refreshToken = response.refreshToken
            if let user = response.user {
                tokenStore.cachedMe = user
            }

            let me = try await api.me()
            tokenStore.cachedMe = me
            return me
        } catch {
            clearStoredCredentials()
            throw mapError(error)
        }
    }

    private func authenticateOnWeb() async throws -> URL {
        guard let startURL = URL(string: AppConfig.mobileAuthStartURL.absoluteString) else {
            throw AuthServiceError.invalidStartURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: startURL,
                callbackURLScheme: AppConfig.mobileAuthCallbackScheme
            ) { [weak self] callbackURL, error in
                self?.webAuthenticationSession = nil

                if let error {
                    continuation.resume(throwing: self?.mapError(error) ?? AuthServiceError.exchangeRejected(error.localizedDescription))
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: AuthServiceError.invalidCallback)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthenticationSession = session

            guard session.start() else {
                self.webAuthenticationSession = nil
                continuation.resume(throwing: AuthServiceError.invalidStartURL)
                return
            }
        }
    }

    private func parseCallback(_ callbackURL: URL) throws -> (code: String, state: String) {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw AuthServiceError.invalidCallback
        }

        let queryItems = components.queryItems ?? []
        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw AuthServiceError.missingCode
        }
        guard let state = queryItems.first(where: { $0.name == "state" })?.value, !state.isEmpty else {
            throw AuthServiceError.missingState
        }

        return (code, state)
    }

    private func clearStoredCredentials() {
        tokenStore.token = nil
        tokenStore.refreshToken = nil
        tokenStore.cachedMe = nil
    }

    private func mapError(_ error: Error) -> Error {
        if let authError = error as? AuthServiceError {
            return authError
        }

        if let sessionError = error as? ASWebAuthenticationSessionError,
           sessionError.code == .canceledLogin {
            return AuthServiceError.userCancelled
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .timedOut:
                return AuthServiceError.networkUnavailable
            default:
                return AuthServiceError.exchangeRejected(urlError.localizedDescription)
            }
        }

        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                return AuthServiceError.invalidToken
            case .transport(let innerError):
                return mapError(innerError)
            case .server(_, let message):
                return AuthServiceError.exchangeRejected(message)
            case .decoding:
                return AuthServiceError.exchangeRejected("Réponse de connexion invalide.")
            case .invalidURL, .noHTTPResponse:
                return AuthServiceError.exchangeRejected(apiError.localizedDescription)
            }
        }

        return AuthServiceError.exchangeRejected(error.localizedDescription)
    }
}

extension AuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let connectedScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        for scene in connectedScenes {
            if let keyWindow = scene.windows.first(where: \.isKeyWindow) {
                return keyWindow
            }
        }

        return connectedScenes.first?.windows.first ?? ASPresentationAnchor()
    }
}
