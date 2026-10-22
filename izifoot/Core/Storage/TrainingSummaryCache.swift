import CryptoKit
import Foundation
import PDFKit

struct TrainingSummaryVersion: Decodable {
    let version: String
    let timeZone: String
}

struct TrainingSummaryScope: Hashable {
    let accountID: String
    let clubID: String?
    let teamID: String?
    let trainingID: String
    let timeZone: String

    fileprivate var key: String {
        TrainingSummaryCache.hash(try! JSONEncoder().encode([accountID, clubID ?? "", teamID ?? "", trainingID, timeZone, "pdf-cache-v1"]))
    }
}

struct CachedTrainingSummary {
    let url: URL
    let document: PDFDocument
}

/// Private durable PDF cache. All disk changes and session invalidation are serialized on main.
@MainActor
final class TrainingSummaryCache {
    static let shared = TrainingSummaryCache()
    private let root: URL
    static let previewDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("training-summary-previews", isDirectory: true)
    private struct Request {
        let id: UUID
        let task: Task<CachedTrainingSummary, Error>
    }
    private var requests: [TrainingSummaryScope: Request] = [:]

    init(directory: URL? = nil) {
        root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("training-summary-cache", isDirectory: true)
    }

    nonisolated fileprivate static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func load(
        scope: TrainingSummaryScope,
        version: @escaping () async throws -> TrainingSummaryVersion,
        download: @escaping () async throws -> PDFDownload,
        sessionIsCurrent: @escaping () -> Bool,
        onGeneration: @escaping () -> Void
    ) async throws -> CachedTrainingSummary {
        if let request = requests[scope] { return try await request.task.value }
        let requestID = UUID()
        let task = Task { () throws -> CachedTrainingSummary in
            let metadata = try await version()
            try Task.checkCancellation()
            guard sessionIsCurrent() else { throw CancellationError() }
            guard Self.validVersion(metadata.version), TimeZone(identifier: metadata.timeZone) != nil else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let canonicalScope = TrainingSummaryScope(accountID: scope.accountID, clubID: scope.clubID,
                teamID: scope.teamID, trainingID: scope.trainingID, timeZone: metadata.timeZone)
            let file = fileURL(scope: canonicalScope, version: metadata.version)
            if let document = Self.validDocument(at: file) {
                return CachedTrainingSummary(url: file, document: document)
            }
            onGeneration()
            let response = try await download()
            try Task.checkCancellation()
            guard sessionIsCurrent() else { throw CancellationError() }
            guard let renderedVersion = response.version, Self.validVersion(renderedVersion),
                  response.data.starts(with: Data("%PDF-".utf8)),
                  let document = PDFDocument(data: response.data), document.pageCount > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            // The response header, not the earlier metadata request, identifies these PDF bytes.
            let destination = fileURL(scope: canonicalScope, version: renderedVersion)
            var directory = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.protectionKey: FileProtectionType.complete])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try response.data.write(to: destination, options: [.atomic, .completeFileProtection])
            // Keep older files until a valid replacement has been saved successfully.
            if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                for old in files where old.lastPathComponent.hasPrefix(canonicalScope.key + "-") && old.lastPathComponent != destination.lastPathComponent {
                    try? FileManager.default.removeItem(at: old)
                }
            }
            return CachedTrainingSummary(url: destination, document: document)
        }
        requests[scope] = Request(id: requestID, task: task)
        defer {
            if requests[scope]?.id == requestID { requests[scope] = nil }
        }
        do {
            return try await task.value
        } catch {
            if case let APIError.server(status, _) = error, status == 403 || status == 404 {
                removeTraining(accountID: scope.accountID, trainingID: scope.trainingID)
            }
            throw error
        }
    }

    func removeTraining(accountID: String, trainingID: String) {
        for (scope, request) in requests where scope.accountID == accountID && scope.trainingID == trainingID {
            request.task.cancel()
            requests[scope] = nil
        }
        try? FileManager.default.removeItem(at: trainingDirectory(accountID: accountID, trainingID: trainingID))
    }

    func removeAll() {
        requests.values.forEach { $0.task.cancel() }
        requests.removeAll()
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: Self.previewDirectory)
    }

    private func trainingDirectory(accountID: String, trainingID: String) -> URL {
        root.appendingPathComponent(Self.hash(Data(accountID.utf8)), isDirectory: true)
            .appendingPathComponent(Self.hash(Data(trainingID.utf8)), isDirectory: true)
    }

    private func fileURL(scope: TrainingSummaryScope, version: String) -> URL {
        trainingDirectory(accountID: scope.accountID, trainingID: scope.trainingID)
            .appendingPathComponent("\(scope.key)-\(version).pdf")
    }

    private static func validVersion(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdef").contains($0) }
    }

    private static func validDocument(at url: URL) -> PDFDocument? {
        guard let data = try? Data(contentsOf: url), data.starts(with: Data("%PDF-".utf8)),
              let document = PDFDocument(data: data), document.pageCount > 0 else { return nil }
        return document
    }
}
