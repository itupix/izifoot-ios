import Combine
import Foundation

protocol AttendanceReportServing {
    func teamAttendanceReport(teamID: String) async throws -> AttendanceReport
}

@MainActor
final class AttendanceReportStore: ObservableObject {
    @Published private(set) var reportScope = ""
    @Published private(set) var report: AttendanceReport?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private let api: AttendanceReportServing
    private var generation = UUID()

    init(api: AttendanceReportServing) { self.api = api }

    func load(teamID: String?, scope: String) async {
        let request = UUID()
        generation = request
        report = nil
        reportScope = ""
        errorMessage = nil
        guard let teamID, !teamID.isEmpty else {
            isLoading = false
            return
        }
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            let fetched = try await api.teamAttendanceReport(teamID: teamID)
            guard generation == request, !Task.isCancelled else { return }
            reportScope = scope
            report = fetched
        } catch {
            guard generation == request, !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = error.localizedDescription
        }
    }
}
