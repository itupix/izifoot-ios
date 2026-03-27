import Foundation

enum AccountRole: String, Codable, CaseIterable {
    case direction = "DIRECTION"
    case coach = "COACH"
    case player = "PLAYER"
    case parent = "PARENT"

    var defaultTab: AppTab {
        switch self {
        case .direction: return .club
        case .coach: return .planning
        case .player, .parent: return .planning
        }
    }

    var canManageClub: Bool {
        self == .direction
    }

    var canEditSportData: Bool {
        self == .direction || self == .coach
    }
}

struct Me: Codable, Identifiable {
    let id: String
    let email: String
    let isPremium: Bool
    let planningCount: Int?
    let role: AccountRole
    let clubId: String?
    let teamId: String?
    let managedTeamIds: [String]
    let linkedPlayerUserId: String?
}

struct Club: Codable, Identifiable {
    let id: String
    let name: String
    let createdAt: String?
}

struct Team: Codable, Identifiable {
    let id: String
    let name: String
    let category: String?
    let format: String?
    let clubId: String?
    let createdAt: String?
}

struct Coach: Codable, Identifiable {
    let id: String
    let email: String?
    let firstName: String?
    let lastName: String?
    let managedTeamIds: [String]?
}

struct Player: Codable, Identifiable {
    let id: String
    let name: String
    let firstName: String?
    let lastName: String?
    let primaryPosition: String?
    let secondaryPosition: String?
    let email: String?
    let phone: String?
    let teamId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case firstName
        case first_name
        case prenom
        case lastName
        case last_name
        case nom
        case primaryPosition = "primary_position"
        case secondaryPosition = "secondary_position"
        case email
        case phone
        case teamId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        firstName = try? container.decodeIfPresent(String.self, forKey: .firstName)
            ?? container.decodeIfPresent(String.self, forKey: .first_name)
            ?? container.decodeIfPresent(String.self, forKey: .prenom)
        lastName = try? container.decodeIfPresent(String.self, forKey: .lastName)
            ?? container.decodeIfPresent(String.self, forKey: .last_name)
            ?? container.decodeIfPresent(String.self, forKey: .nom)
        primaryPosition = try? container.decodeIfPresent(String.self, forKey: .primaryPosition)
        secondaryPosition = try? container.decodeIfPresent(String.self, forKey: .secondaryPosition)
        email = try? container.decodeIfPresent(String.self, forKey: .email)
        phone = try? container.decodeIfPresent(String.self, forKey: .phone)
        teamId = try? container.decodeIfPresent(String.self, forKey: .teamId)
    }

    init(
        id: String,
        name: String,
        firstName: String? = nil,
        lastName: String? = nil,
        primaryPosition: String? = nil,
        secondaryPosition: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        teamId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.firstName = firstName
        self.lastName = lastName
        self.primaryPosition = primaryPosition
        self.secondaryPosition = secondaryPosition
        self.email = email
        self.phone = phone
        self.teamId = teamId
    }
}

struct Training: Codable, Identifiable {
    let id: String
    let date: String
    let status: String?
    let teamId: String?
}

struct Matchday: Codable, Identifiable {
    let id: String
    let date: String
    let lieu: String?
    let address: String?
    let startTime: String?
    let meetingTime: String?
    let teamId: String?
}

struct Drill: Codable, Identifiable {
    let id: String
    let title: String
    let category: String
    let duration: Int
    let players: String
    let description: String
    let descriptionHtml: String?
    let tags: [String]
    let teamId: String?
}

struct DrillsResponse: Codable {
    let items: [Drill]
    let categories: [String]
    let tags: [String]
}

struct AttendanceRow: Codable, Identifiable {
    let id: String?
    let sessionType: String
    let sessionId: String
    let playerId: String
    let present: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case sessionType = "session_type"
        case sessionId = "session_id"
        case playerId
        case present
    }
}

struct MatchScorer: Codable, Identifiable {
    let id: String?
    let playerId: String
    let side: String
    let playerName: String?
}

struct MatchTeamLite: Codable, Identifiable {
    let id: String
    let side: String
    let score: Int
}

struct MatchLite: Codable, Identifiable {
    let id: String
    let createdAt: String
    let type: String
    let matchdayId: String?
    let rotationGameKey: String?
    let status: String?
    let played: Bool?
    let teams: [MatchTeamLite]
    let scorers: [MatchScorer]
    let opponentName: String?
}
