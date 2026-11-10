import Combine
import Foundation

protocol AttendanceReportServing {
    func allClubSeasons(pageSize: Int) async throws -> [Season]
    func teamAttendanceReport(teamID: String, seasonID: String) async throws -> AttendanceReport
}

@MainActor
final class AttendanceReportStore: ObservableObject {
    @Published private(set) var seasons: [Season] = []
    @Published var selectedSeasonID = ""
    @Published private(set) var report: AttendanceReport?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private let api: AttendanceReportServing
    private var generation = UUID()
    private var scopeKey = ""

    init(api: AttendanceReportServing) { self.api = api }

    func load(teamID: String?, scope: String) async {
        let request = UUID()
        generation = request
        let scopeChanged = scopeKey != scope
        scopeKey = scope
        report = nil
        errorMessage = nil
        if scopeChanged {
            seasons = []
            selectedSeasonID = ""
        }
        guard let teamID, !teamID.isEmpty else {
            isLoading = false
            return
        }
        isLoading = true
        defer { if generation == request { isLoading = false } }
        do {
            if seasons.isEmpty {
                let fetched = try await api.allClubSeasons(pageSize: 100)
                guard generation == request, !Task.isCancelled else { return }
                seasons = fetched
                if selectedSeasonID.isEmpty || !fetched.contains(where: { $0.id == selectedSeasonID }) {
                    selectedSeasonID = fetched.first(where: { $0.isCurrent == true })?.id ?? fetched.first?.id ?? ""
                }
            }
            guard !selectedSeasonID.isEmpty else { return }
            let requestedSeasonID = selectedSeasonID
            let fetched = try await api.teamAttendanceReport(teamID: teamID, seasonID: requestedSeasonID)
            guard generation == request, !Task.isCancelled, selectedSeasonID == requestedSeasonID else { return }
            report = fetched
        } catch {
            guard generation == request, !Task.isCancelled , !(error is CancellationError) else { return }
            errorMessage = error.localizedDescription
        }
    }
}
