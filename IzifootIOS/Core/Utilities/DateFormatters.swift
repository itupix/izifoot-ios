import Foundation

enum DateFormatters {
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

    static let frenchDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func parseISODate(_ value: String) -> Date? {
        iso8601WithFractional.date(from: value) ?? iso8601NoFractional.date(from: value)
    }

    static func display(_ value: String) -> String {
        guard let date = parseISODate(value) else { return value }
        return frenchDateTime.string(from: date)
    }

    static func isoString(from date: Date) -> String {
        iso8601WithFractional.string(from: date)
    }
}
