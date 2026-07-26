import Foundation

enum DateFormatters {
    static let isoDateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601NoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let iso8601WithFractionalAndSpace: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withSpaceBetweenDateAndTime]
        return formatter
    }()

    static let iso8601NoFractionalAndSpace: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withSpaceBetweenDateAndTime]
        return formatter
    }()

    static let frenchDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let frenchDateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let frenchMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter
    }()

    static func parseISODate(_ value: String) -> Date? {
        iso8601WithFractional.date(from: value)
            ?? iso8601NoFractional.date(from: value)
            ?? iso8601WithFractionalAndSpace.date(from: value)
            ?? iso8601NoFractionalAndSpace.date(from: value)
            ?? isoDateOnly.date(from: value)
    }

    static func display(_ value: String) -> String {
        guard let date = parseISODate(value) else { return value }
        return frenchDateTime.string(from: date)
    }

    static func displayDateOnly(_ value: String) -> String {
        guard let date = parseISODate(value) else { return value }
        return frenchDateOnly.string(from: date)
    }

    static func isoString(from date: Date) -> String {
        iso8601WithFractional.string(from: date)
    }

    static func isoDateOnlyString(from date: Date) -> String {
        isoDateOnly.string(from: date)
    }
}

struct SeasonDisplayWindow {
    let label: String
    let startDate: Date
    let endDate: Date
}

enum SeasonSupport {
    static let defaultTimezoneIdentifier = "Europe/Paris"
    static let defaultSeasonConfig = ClubSeasonConfig(
        startMonth: 8,
        startDay: 1,
        endMonth: 7,
        endDay: 31,
        timezone: defaultTimezoneIdentifier
    )

    static func displayWindow(for date: Date, config: ClubSeasonConfig?) -> SeasonDisplayWindow {
        let resolvedConfig = config ?? defaultSeasonConfig
        let calendar = gregorianCalendar(timezoneIdentifier: resolvedConfig.timezone)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let month = components.month ?? 1
        let day = components.day ?? 1
        let year = components.year ?? currentNonLeapReferenceYear()
        let startsThisYear = compareMonthDay(
            lhsMonth: month,
            lhsDay: day,
            rhsMonth: resolvedConfig.startMonth,
            rhsDay: resolvedConfig.startDay
        ) >= 0
        let startYear = startsThisYear ? year : year - 1
        let endYear = startYear + 1
        let startDate = calendar.date(from: DateComponents(
            year: startYear,
            month: resolvedConfig.startMonth,
            day: resolvedConfig.startDay
        )) ?? date
        let endDate = calendar.date(from: DateComponents(
            year: endYear,
            month: resolvedConfig.endMonth,
            day: resolvedConfig.endDay
        )) ?? date

        return SeasonDisplayWindow(
            label: "\(startYear)-\(endYear)",
            startDate: startDate,
            endDate: endDate
        )
    }

    static func matchingSeason(in seasons: [Season], for date: Date) -> Season? {
        seasons.first { season in
            guard
                let startDate = DateFormatters.parseISODate(season.startDate),
                let endDate = DateFormatters.parseISODate(season.endDate)
            else {
                return false
            }
            return date >= startDate && date <= endDate
        }
    }

    static func rangeLabel(for season: Season) -> String {
        "\(DateFormatters.displayDateOnly(season.startDate)) - \(DateFormatters.displayDateOnly(season.endDate))"
    }

    static func rangeLabel(for window: SeasonDisplayWindow) -> String {
        "\(DateFormatters.frenchDateOnly.string(from: window.startDate)) - \(DateFormatters.frenchDateOnly.string(from: window.endDate))"
    }

    static func monthDayLabel(for date: Date) -> String {
        DateFormatters.frenchMonthDay.string(from: date)
    }

    static func referenceDates(for config: ClubSeasonConfig, referenceYear: Int = currentNonLeapReferenceYear()) -> (startDate: Date, endDate: Date) {
        let calendar = gregorianCalendar(timezoneIdentifier: config.timezone)
        let startDate = calendar.date(from: DateComponents(
            year: referenceYear,
            month: config.startMonth,
            day: config.startDay
        )) ?? Date()
        let endDate = calendar.date(from: DateComponents(
            year: referenceYear + 1,
            month: config.endMonth,
            day: config.endDay
        )) ?? Date()
        return (startDate, endDate)
    }

    static func validStartDateRange(referenceYear: Int = currentNonLeapReferenceYear()) -> ClosedRange<Date> {
        let calendar = gregorianCalendar()
        let start = calendar.date(from: DateComponents(year: referenceYear, month: 1, day: 2)) ?? Date()
        let end = calendar.date(from: DateComponents(year: referenceYear, month: 12, day: 31)) ?? start
        return start ... end
    }

    static func validEndDateRange(for startDate: Date) -> ClosedRange<Date>? {
        let calendar = gregorianCalendar()
        let startComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        guard
            let startYear = startComponents.year,
            let startMonth = startComponents.month,
            let startDay = startComponents.day
        else {
            return nil
        }

        let nextYear = startYear + 1
        guard
            let minimum = calendar.date(from: DateComponents(year: nextYear, month: 1, day: 1)),
            let nextSeasonStart = calendar.date(from: DateComponents(year: nextYear, month: startMonth, day: startDay)),
            let maximum = calendar.date(byAdding: .day, value: -1, to: nextSeasonStart),
            minimum <= maximum
        else {
            return nil
        }

        return minimum ... maximum
    }

    static func seasonConfig(from startDate: Date, endDate: Date, timezone: String? = defaultTimezoneIdentifier) -> ClubSeasonConfig {
        let calendar = gregorianCalendar(timezoneIdentifier: timezone)
        let startComponents = calendar.dateComponents([.month, .day], from: startDate)
        let endComponents = calendar.dateComponents([.month, .day], from: endDate)
        return ClubSeasonConfig(
            startMonth: startComponents.month ?? defaultSeasonConfig.startMonth,
            startDay: startComponents.day ?? defaultSeasonConfig.startDay,
            endMonth: endComponents.month ?? defaultSeasonConfig.endMonth,
            endDay: endComponents.day ?? defaultSeasonConfig.endDay,
            timezone: timezone ?? defaultTimezoneIdentifier
        )
    }

    static func compareMonthDay(lhsMonth: Int, lhsDay: Int, rhsMonth: Int, rhsDay: Int) -> Int {
        if lhsMonth != rhsMonth {
            return lhsMonth < rhsMonth ? -1 : 1
        }
        if lhsDay != rhsDay {
            return lhsDay < rhsDay ? -1 : 1
        }
        return 0
    }

    static func currentNonLeapReferenceYear() -> Int {
        var year = Calendar(identifier: .gregorian).component(.year, from: Date())
        while isLeapYear(year) {
            year += 1
        }
        return year
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        if year % 400 == 0 { return true }
        if year % 100 == 0 { return false }
        return year % 4 == 0
    }

    private static func gregorianCalendar(timezoneIdentifier: String? = nil) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let timezoneIdentifier,
           let timezone = TimeZone(identifier: timezoneIdentifier) {
            calendar.timeZone = timezone
        } else if let timezone = TimeZone(identifier: defaultTimezoneIdentifier) {
            calendar.timeZone = timezone
        }
        return calendar
    }
}
