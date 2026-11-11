import Foundation
import PDFKit

@main struct AttendancePDFChecks {
    @MainActor static func main() async throws {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let bytes = document.dataRepresentation()!
        let store = AttendancePDFStore()
        var pending: CheckedContinuation<Data, Error>?
        var calls = 0
        let old = Task {
            await store.load(month: "2026-09", download: {
                calls += 1
                return try await withCheckedThrowingContinuation { pending = $0 }
            }, isCurrent: { true })
        }
        while pending == nil { await Task.yield() }
        precondition(store.isLoading)
        await store.load(month: "2026-09", download: { calls += 1; return bytes }, isCurrent: { true })
        precondition(calls == 1, "Repeated taps must not create duplicate downloads")
        store.invalidate()
        await store.load(month: "2026-10", download: { bytes }, isCurrent: { true })
        let currentURL = store.preview!.url
        precondition(currentURL.lastPathComponent == "presences-2026-10.pdf")
        precondition(store.preview!.document.pageCount == 1 && FileManager.default.fileExists(atPath: currentURL.path))
        pending!.resume(returning: bytes)
        await old.value
        precondition(store.preview?.url == currentURL, "Previous scope must not replace current PDF")
        store.invalidate()
        precondition(!FileManager.default.fileExists(atPath: currentURL.path), "Dismissal removes private temporary PDF")
        await store.load(month: "2026-10", download: { Data("%PDF-invalid".utf8) }, isCurrent: { true })
        precondition(store.preview == nil && store.errorMessage != nil && !store.isLoading)
        await store.load(month: "2026-10", download: { bytes }, isCurrent: { false })
        precondition(store.preview == nil && store.errorMessage == nil, "Changed month/team/mode/auth must discard downloaded bytes")
        await store.load(month: "2026-10", download: { throw URLError(.notConnectedToInternet) }, isCurrent: { true })
        precondition(store.errorMessage != nil && !store.isLoading)
        await store.load(month: "2026-10", download: { bytes }, isCurrent: { true })
        precondition(store.preview != nil && store.errorMessage == nil, "Error must support retry")
        store.invalidate()
        print("PASS: valid PDF preview, filename, duplicate taps, stale scope, invalid PDF, retry, temporary-file cleanup")
    }
}
