import Foundation
protocol TokenStoreProtocol: AnyObject { var token: String? { get set }; var refreshToken: String? { get set }; var cachedMe: String? { get set } }
final class TokenStore: TokenStoreProtocol { static let shared = TokenStore(); var token: String? = "test-token"; var refreshToken: String?; var cachedMe: String? }
final class AppSession { static let shared = AppSession(); var activeTeamID: String? = "team" }
enum AppConfig { static let apiBaseURL = URL(string: "https://example.invalid")! }
struct EmptyResponse: Decodable { let ok: Bool }
final class StubProtocol: URLProtocol {
    static var status = 200
    static var mime = "application/pdf"
    static var body = Data("%PDF-1.4\nexample".utf8)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.httpMethod == "GET")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        precondition(request.value(forHTTPHeaderField: "X-Team-Id") == "team")
        precondition(request.value(forHTTPHeaderField: "Accept") == "application/pdf")
        precondition(request.cachePolicy == .reloadIgnoringLocalCacheData)
        client!.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": Self.mime])!, cacheStoragePolicy: .notAllowed)
        client!.urlProtocol(self, didLoad: Self.body)
        client!.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct Checks {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let store = TokenStore()
        let client = APIClient(session: URLSession(configuration: config), tokenStore: store)
        let data = try await client.get("/trainings/id/summary.pdf?timeZone=Europe%2FParis", responseType: Data.self)
        precondition(data == StubProtocol.body)
        StubProtocol.mime = "application/json"
        do { let _: Data = try await client.get("/pdf", responseType: Data.self); fatalError("Accepted non-PDF") } catch APIError.server { }
        StubProtocol.mime = "application/pdf"
        StubProtocol.body = Data("not a PDF".utf8)
        do { let _: Data = try await client.get("/pdf", responseType: Data.self); fatalError("Accepted invalid PDF") } catch APIError.server { }
        StubProtocol.status = 500
        StubProtocol.mime = "application/json"
        StubProtocol.body = Data("{\"error\":\"Failed to generate training summary\"}".utf8)
        do { let _: Data = try await client.get("/pdf", responseType: Data.self); fatalError("Accepted server error") } catch APIError.server(let status, let message) { precondition(status == 500 && message == "Failed to generate training summary") }
        StubProtocol.status = 401
        do { let _: Data = try await client.get("/pdf", responseType: Data.self); fatalError("Accepted unauthorized") } catch APIError.unauthorized { precondition(store.token == nil && AppSession.shared.activeTeamID == nil) }
        print("PASS: PDF bytes, auth/team headers, cache bypass, invalid payloads, server errors, expired session")
    }
}
