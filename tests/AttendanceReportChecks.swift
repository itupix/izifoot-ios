import Foundation

private let fixture = """
{"teamId":"team","season":{"id":"season","key":"2026-2027","label":"2026-2027","startDate":"2026-08-01","endDate":"2027-07-31"},"generatedAt":"2026-11-10T10:00:00Z","summary":{"presentCount":1,"absentCount":1,"unrecordedCount":1,"recordedCount":2,"attendanceRate":50},"months":[{"month":"2026-09","summary":{"presentCount":0,"absentCount":0,"unrecordedCount":1,"recordedCount":0,"attendanceRate":null}}],"trainings":[{"id":"training","date":"2026-09-01T18:00:00Z","endTime":null,"status":"PLANNED","month":"2026-09","includedInRate":true}],"players":[{"id":"p","name":"Émile","first_name":null,"last_name":null,"is_active":false,"summary":{"presentCount":1,"absentCount":1,"unrecordedCount":1,"recordedCount":2,"attendanceRate":50},"months":[],"attendances":[{"trainingId":"training","status":"UNRECORDED"}]}]}
"""

private actor ReportAPI: AttendanceReportServing {
    var requestedTeams: [String] = []
    func allClubSeasons(pageSize: Int) async throws -> [Season] {
        [Season(id: "season", clubId: "club", key: "2026-2027", label: "2026-2027", startDate: "2026-08-01", endDate: "2027-07-31", isCurrent: true)]
    }
    func teamAttendanceReport(teamID: String, seasonID: String) async throws -> AttendanceReport {
        requestedTeams.append(teamID)
        if teamID == "old" { try? await Task.sleep(nanoseconds: 80_000_000) }
        return try JSONDecoder().decode(AttendanceReport.self, from: Data(fixture.replacingOccurrences(of: "\"teamId\":\"team\"", with: "\"teamId\":\"\(teamID)\"").utf8))
    }
}

@main struct AttendanceReportChecks {
    @MainActor static func main() async throws {
        let report = try JSONDecoder().decode(AttendanceReport.self, from: Data(fixture.utf8))
        precondition(report.summary.percentage == "50 %")
        precondition(report.months[0].summary.percentage == "—")
        precondition(report.players[0].status(for: "training") == .unrecorded)
        precondition(report.players[0].status(for: "missing") == nil)
        precondition(report.players[0].is_active == false)
        let now = ISO8601DateFormatter().date(from: "2026-11-10T10:00:00Z")!
        precondition(report.defaultMonth(now: now) == "2026-09")
        for raw in ["PRESENT", "ABSENT", "UNRECORDED", "UPCOMING", "CANCELLED", "NOT_APPLICABLE"] {
            let status = try JSONDecoder().decode(AttendanceReport.Status.self, from: Data("\"\(raw)\"".utf8))
            precondition(!status.label.isEmpty && !status.symbol.isEmpty)
        }
        let api = ReportAPI()
        let store = AttendanceReportStore(api: api)
        let old = Task { await store.load(teamID: "old", scope: "old") }
        while !(await api.requestedTeams.contains("old")) { await Task.yield() }
        await store.load(teamID: "new", scope: "new")
        await old.value
        precondition(store.report?.teamId == "new", "Late previous-team response must not overwrite new scope")
        await store.load(teamID: nil, scope: "all")
        precondition(store.report == nil && store.seasons.isEmpty && !store.isLoading)
        print("PASS: report decoding, null percentages, all statuses, default month, stale team request rejection, all-team clearing")
    }
}
