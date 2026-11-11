import Combine
import Foundation
import PDFKit

struct AttendancePDFPreview {
    let url: URL
    let document: PDFDocument
}

@MainActor
final class AttendancePDFStore: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var preview: AttendancePDFPreview?
    @Published private(set) var errorMessage: String?
    private var generation = UUID()

    func invalidate() {
        generation = UUID()
        isLoading = false
        errorMessage = nil
        if let preview { try? FileManager.default.removeItem(at: preview.url.deletingLastPathComponent()) }
        preview = nil
    }

    func load(month: String, download: () async throws -> Data, isCurrent: () -> Bool) async {
        guard !isLoading else { return }
        invalidate()
        let request = generation
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            let bytes = try await download()
            guard generation == request, isCurrent(), !Task.isCancelled else { return }
            guard bytes.starts(with: Data("%PDF-".utf8)), let document = PDFDocument(data: bytes), document.pageCount > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("attendance-pdf-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("presences-\(month).pdf")
            do { try bytes.write(to: url, options: [.atomic, .completeFileProtection]) }
            catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
            preview = AttendancePDFPreview(url: url, document: document)
        } catch {
            guard generation == request, isCurrent(), !Task.isCancelled else { return }
            errorMessage = "Impossible de préparer le rapport PDF. Réessayez."
        }
    }
}
