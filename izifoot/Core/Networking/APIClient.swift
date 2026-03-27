import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case noHTTPResponse
    case unauthorized
    case server(status: Int, message: String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL API invalide"
        case .noHTTPResponse:
            return "Réponse API invalide"
        case .unauthorized:
            return "Session expirée. Veuillez vous reconnecter."
        case let .server(_, message):
            return message
        case let .decoding(error):
            return "Erreur de lecture des données: \(error.localizedDescription)"
        case let .transport(error):
            return error.localizedDescription
        }
    }
}

protocol APIClientProtocol {
    func get<T: Decodable>(_ path: String, responseType: T.Type) async throws -> T
    func post<T: Decodable, Body: Encodable>(_ path: String, body: Body, responseType: T.Type) async throws -> T
    func put<T: Decodable, Body: Encodable>(_ path: String, body: Body, responseType: T.Type) async throws -> T
    func delete<T: Decodable>(_ path: String, responseType: T.Type) async throws -> T
}

final class APIClient: APIClientProtocol {
    static let shared = APIClient()

    private let session: URLSession
    private let tokenStore: TokenStoreProtocol
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared, tokenStore: TokenStoreProtocol = TokenStore.shared) {
        self.session = session
        self.tokenStore = tokenStore
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func get<T: Decodable>(_ path: String, responseType: T.Type = T.self) async throws -> T {
        try await request(path: path, method: "GET", body: Optional<String>.none)
    }

    func post<T: Decodable, Body: Encodable>(_ path: String, body: Body, responseType: T.Type = T.self) async throws -> T {
        try await request(path: path, method: "POST", body: body)
    }

    func put<T: Decodable, Body: Encodable>(_ path: String, body: Body, responseType: T.Type = T.self) async throws -> T {
        try await request(path: path, method: "PUT", body: body)
    }

    func delete<T: Decodable>(_ path: String, responseType: T.Type = T.self) async throws -> T {
        try await request(path: path, method: "DELETE", body: Optional<String>.none)
    }

    private func request<T: Decodable, Body: Encodable>(path: String, method: String, body: Body?) async throws -> T {
        guard let url = URL(string: path, relativeTo: AppConfig.apiBaseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = tokenStore.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let activeTeamID = AppSession.shared.activeTeamID, !activeTeamID.isEmpty {
            request.setValue(activeTeamID, forHTTPHeaderField: "X-Team-Id")
            request.setValue(activeTeamID, forHTTPHeaderField: "X-Active-Team-Id")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.noHTTPResponse
            }

            guard 200 ... 299 ~= httpResponse.statusCode else {
                if httpResponse.statusCode == 401 {
                    throw APIError.unauthorized
                }
                let message = Self.parseMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
                throw APIError.server(status: httpResponse.statusCode, message: message)
            }

            do {
                if data.isEmpty, let emptyResponse = EmptyResponse(ok: true) as? T {
                    return emptyResponse
                }
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }

    private static func parseMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return String(data: data, encoding: .utf8)
        }

        if let error = object["error"] as? String, !error.isEmpty {
            return error
        }
        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        return nil
    }
}
