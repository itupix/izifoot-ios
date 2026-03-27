import Foundation

final class AppSession {
    static let shared = AppSession()

    var activeTeamID: String?

    private init() {}
}
