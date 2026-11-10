import Foundation

struct AttendanceReport: Decodable {
    struct ReportSeason: Decodable {
        let id: String
        let key: String
        let label: String
        let startDate: String
        let endDate: String
    }
    struct Stats: Decodable {
        let presentCount: Int
        let absentCount: Int
        let unrecordedCount: Int
        let recordedCount: Int
        let attendanceRate: Double?

        var percentage: String {
            guard let attendanceRate else { return "—" }
            return attendanceRate.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...1))) + " %"
        }
    }
    struct Month: Decodable, Identifiable {
        let month: String
        let summary: Stats
        var id: String { month }
    }
    struct Training: Decodable, Identifiable {
        let id: String
        let date: String
        let endTime: String?
        let status: String
        let month: String
        let includedInRate: Bool
    }
    struct Entry: Decodable {
        let trainingId: String
        let status: Status
    }
    enum Status: String, Decodable {
        case present = "PRESENT", absent = "ABSENT", unrecorded = "UNRECORDED"
        case upcoming = "UPCOMING", cancelled = "CANCELLED", notApplicable = "NOT_APPLICABLE"

        var label: String {
            switch self {
            case .present: return "Présent"
            case .absent: return "Absent"
            case .unrecorded: return "Non renseigné"
            case .upcoming: return "À venir"
            case .cancelled: return "Annulé"
            case .notApplicable: return "Hors effectif à cette date"
            }
        }
        var symbol: String {
            switch self {
            case .present: return "checkmark.circle"
            case .absent: return "xmark.circle"
            case .unrecorded: return "questionmark.circle"
            case .upcoming: return "clock"
            case .cancelled: return "calendar.badge.minus"
            case .notApplicable: return "minus.circle"
            }
        }
    }
    struct Player: Decodable, Identifiable {
        let id: String
        let name: String
        let first_name: String?
        let last_name: String?
        let is_active: Bool
        let summary: Stats
        let months: [Month]
        let attendances: [Entry]

        var displayName: String {
            let fullName = [first_name, last_name].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
            return fullName.isEmpty ? name : fullName
        }

        func status(for trainingID: String) -> Status? {
            attendances.first { $0.trainingId == trainingID }?.status
        }
    }
    let teamId: String
    let season: ReportSeason
    let generatedAt: String
    let summary: Stats
    let months: [Month]
    let trainings: [Training]
    let players: [Player]

    var matrixPlayers: [Player] {
        players.sorted {
            let order = $0.displayName.compare($1.displayName, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    func matrixTrainings(in month: String) -> [Training] {
        trainings.filter { $0.month == month }.sorted {
            let lhs = Self.parseTrainingDate($0.date)
            let rhs = Self.parseTrainingDate($1.date)
            if let lhs, let rhs, lhs != rhs { return lhs < rhs }
            return $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
        }
    }

    private static func parseTrainingDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func trainingDateLabel(_ value: String, style: DateFormatter.Style = .medium, compact: Bool = false) -> String {
        guard let date = parseTrainingDate(value) else { return String(value.prefix(10)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = TimeZone(identifier: "Europe/Paris")
        formatter.dateStyle = style
        formatter.timeStyle = .none
        if compact { formatter.dateFormat = "dd/MM" }
        return formatter.string(from: date)
    }

    func defaultMonth(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Paris")
        formatter.dateFormat = "yyyy-MM"
        let current = formatter.string(from: now)
        if months.contains(where: { $0.month == current }) { return current }
        return trainings.map(\.month).max() ?? months.last?.month ?? ""
    }

    static func monthLabel(_ month: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM"
        guard let date = input.date(from: month) else { return month }
        input.locale = Locale(identifier: "fr_FR")
        input.dateFormat = "MMMM yyyy"
        return input.string(from: date).capitalized
    }
}
