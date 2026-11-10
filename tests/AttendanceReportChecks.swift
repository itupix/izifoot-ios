import Foundation

private let fixture = """
{"teamId":"team","season":{"id":"season","key":"2026-2027","label":"2026-2027","startDate":"2026-08-01","endDate":"2027-07-31"},"generatedAt":"2026-11-10T10:00:00Z","summary":{"presentCount":1,"absentCount":1,"unrecordedCount":1,"recordedCount":2,"attendanceRate":50},"months":[{"month":"2026-09","summary":{"presentCount":0,"absentCount":0,"unrecordedCount":1,"recordedCount":0,"attendanceRate":null}}],"trainings":[{"id":"training","date":"2026-09-01T18:00:00Z","endTime":null,"status":"PLANNED","month":"2026-09","includedInRate":true}],"players":[{"id":"p","name":"Émile","first_name":null,"last_name":null,"is_active":true,"summary":{"presentCount":1,"absentCount":1,"unrecordedCount":1,"recordedCount":2,"attendanceRate":50},"months":[],"attendances":[{"trainingId":"training","status":"UNRECORDED"}]}]}
"""

private actor ReportAPI: AttendanceReportServing {
    var requestedTeams: [String] = []
    func teamAttendanceReport(teamID: String) async throws -> AttendanceReport {
        requestedTeams.append(teamID)
        if teamID == "failure" { throw URLError(.notConnectedToInternet) }
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
        precondition(report.players[0].is_active == true)
        let now = ISO8601DateFormatter().date(from: "2026-11-10T10:00:00Z")!
        precondition(report.defaultMonth(now: now) == "2026-09")
        for raw in ["PRESENT", "ABSENT", "UNRECORDED", "UPCOMING", "CANCELLED", "NOT_APPLICABLE"] {
            let status = try JSONDecoder().decode(AttendanceReport.Status.self, from: Data("\"\(raw)\"".utf8))
            precondition(!status.label.isEmpty && !status.symbol.isEmpty)
        }
        var matrixJSON = try JSONSerialization.jsonObject(with: Data(fixture.utf8)) as! [String: Any]
        let basePlayer = (matrixJSON["players"] as! [[String: Any]])[0]
        matrixJSON["players"] = ["Zoé", "Émile", "Anaïs"].enumerated().map { index, name -> [String: Any] in
            var player = basePlayer
            player["id"] = "p\(index)"
            player["name"] = "legacy-\(index)"
            player["first_name"] = name
            return player
        }
        let baseTraining = (matrixJSON["trainings"] as! [[String: Any]])[0]
        matrixJSON["trainings"] = [
            ("late", "2026-09-01T20:00:00+02:00", "2026-09"),
            ("other-month", "2026-10-01T10:00:00Z", "2026-10"),
            ("early", "2026-09-01T17:00:00Z", "2026-09")
        ].map { id, date, month -> [String: Any] in
            var training = baseTraining
            training["id"] = id
            training["date"] = date
            training["month"] = month
            return training
        }
        let matrix = try JSONDecoder().decode(AttendanceReport.self, from: JSONSerialization.data(withJSONObject: matrixJSON))
        precondition(matrix.matrixPlayers.map(\.displayName) == ["Anaïs", "Émile", "Zoé"])
        precondition(matrix.matrixTrainings(in: "2026-09").map(\.id) == ["early", "late"], "Same-day columns must use actual chronological time and filter month")
        precondition(matrix.matrixTrainings(in: "2026-12").isEmpty)
        precondition(AttendanceReport.trainingDateLabel("2026-09-01T17:00:00Z", compact: true) == "01/09")
        precondition(AttendanceReport.trainingDateLabel("2026-09-01T20:00:00+02:00", compact: true) == "01/09", "Same-day sessions remain separate columns with date-only labels")
        precondition(!AttendanceReport.trainingDateLabel("2026-09-01T17:00:00Z", style: .full).contains(":"), "Accessible date must omit time")
        precondition(AttendanceReport.trainingDateLabel("2026-08-31T23:00:00Z", compact: true) == "01/09", "Date-only labels preserve Paris calendar date")
        let api = ReportAPI()
        let store = AttendanceReportStore(api: api)
        let old = Task { await store.load(teamID: "old", scope: "old") }
        while !(await api.requestedTeams.contains("old")) { await Task.yield() }
        await store.load(teamID: "new", scope: "new")
        await old.value
        let requestedTeams = await api.requestedTeams
        precondition(requestedTeams == ["old", "new"])
        precondition(store.report?.teamId == "new", "Late previous-team response must not overwrite new scope")
        precondition(store.reportScope == "new")
        await store.load(teamID: "failure", scope: "failure")
        precondition(store.report == nil && store.errorMessage != nil && !store.isLoading, "Current-season failure must clear previous report without historical fallback")
        await store.load(teamID: nil, scope: "all")
        precondition(store.report == nil && !store.isLoading)
        print("PASS: date-only matrix/detail/accessibility labels, French alphabetical matrix, chronological same-day columns, month filtering, report decoding, null percentages, all statuses, default month, current-season-only requests, stale team request rejection, failure clears old report without fallback, all-team clearing")
    }
}
