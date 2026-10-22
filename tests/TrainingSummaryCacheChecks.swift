import Foundation
import CoreGraphics
import PDFKit

protocol TokenStoreProtocol: AnyObject { var token: String? { get set }; var refreshToken: String? { get set }; var cachedMe: String? { get set } }
final class TokenStore: TokenStoreProtocol { static let shared = TokenStore(); var token: String?; var refreshToken: String?; var cachedMe: String? }
final class AppSession { static let shared = AppSession(); var activeTeamID: String? }
enum AppConfig { static let apiBaseURL = URL(string: "https://example.invalid")! }
struct EmptyResponse: Decodable { let ok: Bool }

@MainActor final class Server {
    var checks = 0
    var downloads = 0
    var generating = 0
    var revision = String(repeating: "a", count: 64)
    var renderedRevision: String?
    var zone = "Europe/Paris"
    var failsCheck = false
    var checkError: APIError?
    var omitHeader = false
    var validSession = true
    let data: Data
    init(data: Data) { self.data = data }
    func open(_ cache: TrainingSummaryCache, _ scope: TrainingSummaryScope) async throws -> CachedTrainingSummary {
        try await cache.load(scope: scope, version: {
            self.checks += 1
            try await Task.sleep(for: .milliseconds(5))
            if self.failsCheck { throw URLError(.notConnectedToInternet) }
            if let error = self.checkError { throw error }
            return TrainingSummaryVersion(version: self.revision, timeZone: self.zone)
        }, download: {
            self.downloads += 1
            return PDFDownload(data: self.data, version: self.omitHeader ? nil : (self.renderedRevision ?? self.revision))
        }, sessionIsCurrent: { self.validSession }, onGeneration: { self.generating += 1 })
    }
}

@main struct Checks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.pdf")
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = CGContext(source as CFURL, mediaBox: &box, nil)!
        context.beginPDFPage(nil); context.fill(CGRect(x: 20, y: 20, width: 30, height: 30)); context.endPDFPage(); context.closePDF()
        let server = Server(data: try Data(contentsOf: source))
        let location = root.appendingPathComponent("cache")
        let cache = TrainingSummaryCache(directory: location)
        let scope = TrainingSummaryScope(accountID: "coach", clubID: "club", teamID: "team", trainingID: "session", timeZone: "Europe/Paris")
        let first = try await server.open(cache, scope)
        precondition(server.downloads == 1 && server.checks == 1 && server.generating == 1)
        // Recreating the service simulates app relaunch; a hit still checks version but never renders/downloads.
        let reopenedCache = TrainingSummaryCache(directory: location)
        let hit = try await server.open(reopenedCache, scope)
        precondition(hit.url == first.url && server.downloads == 1 && server.checks == 2 && server.generating == 1, "hit paths=\(hit.url.path) first=\(first.url.path) calls=\(server.downloads)/\(server.checks)/\(server.generating)")
        try Data("corrupt".utf8).write(to: hit.url)
        _ = try await server.open(cache, scope)
        precondition(server.downloads == 2)
        server.revision = String(repeating: "b", count: 64)
        let changed = try await server.open(cache, scope)
        precondition(server.downloads == 3 && !FileManager.default.fileExists(atPath: first.url.path))
        // Metadata/render race: store the header revision, then reuse that exact rendered snapshot.
        server.revision = String(repeating: "c", count: 64)
        server.renderedRevision = String(repeating: "d", count: 64)
        let raced = try await server.open(cache, scope)
        server.revision = server.renderedRevision!; server.renderedRevision = nil
        let racedHit = try await server.open(cache, scope)
        precondition(raced.url == racedHit.url && server.downloads == 4)
        server.failsCheck = true
        do { _ = try await server.open(cache, scope); fatalError("Opened stale PDF offline") } catch is URLError {}
        precondition(server.downloads == 4)
        server.failsCheck = false
        // Alias and canonical timezone identify the same cache after metadata canonicalization.
        let alias = TrainingSummaryScope(accountID: "coach", clubID: "club", teamID: "team", trainingID: "session", timeZone: "CET")
        _ = try await server.open(cache, alias)
        precondition(server.downloads == 4)
        for isolated in [
            TrainingSummaryScope(accountID: "other", clubID: "club", teamID: "team", trainingID: "session", timeZone: "Europe/Paris"),
            TrainingSummaryScope(accountID: "coach", clubID: "other", teamID: "team", trainingID: "session", timeZone: "Europe/Paris"),
            TrainingSummaryScope(accountID: "coach", clubID: "club", teamID: "other", trainingID: "session", timeZone: "Europe/Paris")
        ] { _ = try await server.open(cache, isolated) }
        precondition(server.downloads == 7)
        server.zone = "UTC"
        let utc = TrainingSummaryScope(accountID: "coach", clubID: "club", teamID: "team", trainingID: "session", timeZone: "UTC")
        _ = try await server.open(cache, utc)
        precondition(server.downloads == 8)
        server.zone = "Europe/Paris"; server.revision = String(repeating: "e", count: 64)
        async let one = server.open(cache, scope)
        async let two = server.open(cache, scope)
        let (a, b) = try await (one, two)
        precondition(a.url == b.url && server.downloads == 9)
        server.renderedRevision = "invalid"; server.revision = String(repeating: "f", count: 64)
        do { _ = try await server.open(cache, scope); fatalError("Cached invalid version header") } catch is CocoaError {}
        precondition(server.downloads == 10 && FileManager.default.fileExists(atPath: a.url.path))
        server.renderedRevision = nil
        server.validSession = false
        do { _ = try await server.open(cache, scope); fatalError("Opened cache from expired session") } catch is CancellationError {}
        precondition(server.downloads == 10)
        server.validSession = true
        server.omitHeader = true
        do { _ = try await server.open(cache, scope); fatalError("Cached PDF with missing version header") } catch is CocoaError {}
        server.omitHeader = false
        for status in [403, 404] {
            let authorized = try await server.open(cache, scope)
            server.checkError = .server(status: status, message: "Access denied or missing")
            do { _ = try await server.open(cache, scope); fatalError("Opened PDF after access denial") } catch APIError.server {}
            precondition(!FileManager.default.fileExists(atPath: authorized.url.path))
            server.checkError = nil
        }
        cache.removeTraining(accountID: "coach", trainingID: "session")
        precondition(!FileManager.default.fileExists(atPath: a.url.path) && !FileManager.default.fileExists(atPath: changed.url.path))
        cache.removeAll()
        precondition(!FileManager.default.fileExists(atPath: location.path))
        print("PASS: version checks, persistent hits with zero PDF calls, corrupt/missing/changed cache, render-header race, offline rejection, canonical timezone, account/club/team/timezone isolation, deduplication, invalid/missing header/session rejection, 403/404 invalidation and purge")
    }
}
