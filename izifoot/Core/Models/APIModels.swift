import Foundation

enum AccountRole: String, Codable, CaseIterable {
    case direction = "DIRECTION"
    case coach = "COACH"
    case player = "PLAYER"
    case parent = "PARENT"

    var defaultTab: AppTab {
        switch self {
        case .direction: return .planning
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
    let firstName: String?
    let lastName: String?
    let phone: String?
    let isPremium: Bool
    let planningCount: Int?
    let role: AccountRole
    let clubId: String?
    let teamId: String?
    let managedTeamIds: [String]
    let linkedPlayerUserId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case firstName
        case first_name
        case prenom
        case lastName
        case last_name
        case nom
        case phone
        case telephone
        case isPremium
        case planningCount
        case role
        case clubId
        case teamId
        case managedTeamIds
        case linkedPlayerUserId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        firstName = try? container.decodeIfPresent(String.self, forKey: .firstName)
            ?? container.decodeIfPresent(String.self, forKey: .first_name)
            ?? container.decodeIfPresent(String.self, forKey: .prenom)
        lastName = try? container.decodeIfPresent(String.self, forKey: .lastName)
            ?? container.decodeIfPresent(String.self, forKey: .last_name)
            ?? container.decodeIfPresent(String.self, forKey: .nom)
        phone = try? container.decodeIfPresent(String.self, forKey: .phone)
            ?? container.decodeIfPresent(String.self, forKey: .telephone)
        isPremium = (try? container.decodeIfPresent(Bool.self, forKey: .isPremium)) ?? false
        planningCount = try? container.decodeIfPresent(Int.self, forKey: .planningCount)
        role = try container.decode(AccountRole.self, forKey: .role)
        clubId = try? container.decodeIfPresent(String.self, forKey: .clubId)
        teamId = try? container.decodeIfPresent(String.self, forKey: .teamId)
        managedTeamIds = (try? container.decodeIfPresent([String].self, forKey: .managedTeamIds)) ?? []
        linkedPlayerUserId = try? container.decodeIfPresent(String.self, forKey: .linkedPlayerUserId)
    }
}


struct LinkedChildProfile: Codable, Identifiable {
    let id: String
    let name: String?
    let firstName: String?
    let lastName: String?
    let licence: String?
    let teamId: String?
    let teamName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case firstName
        case first_name
        case prenom
        case lastName
        case last_name
        case nom
        case licence
        case license
        case teamId
        case team_id
        case teamName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        firstName = try? container.decodeIfPresent(String.self, forKey: .firstName)
            ?? container.decodeIfPresent(String.self, forKey: .first_name)
            ?? container.decodeIfPresent(String.self, forKey: .prenom)
        lastName = try? container.decodeIfPresent(String.self, forKey: .lastName)
            ?? container.decodeIfPresent(String.self, forKey: .last_name)
            ?? container.decodeIfPresent(String.self, forKey: .nom)
        licence = try? container.decodeIfPresent(String.self, forKey: .licence)
            ?? container.decodeIfPresent(String.self, forKey: .license)
        teamId = try? container.decodeIfPresent(String.self, forKey: .teamId)
            ?? container.decodeIfPresent(String.self, forKey: .team_id)
        teamName = try? container.decodeIfPresent(String.self, forKey: .teamName)
    }
}

struct TeamMessageAuthor: Codable {
    let id: String
    let firstName: String?
    let lastName: String?
    let role: AccountRole
}

struct TeamMessage: Codable, Identifiable {
    let id: String
    let teamId: String
    let clubId: String
    let content: String
    let createdAt: String
    let updatedAt: String
    let author: TeamMessageAuthor?
    let likesCount: Int
    let likedByMe: Bool
}

struct TeamMessagesResponse: Codable {
    let items: [TeamMessage]
}

struct TeamMessageReactionResponse: Codable {
    let ok: Bool
    let likesCount: Int
    let likedByMe: Bool
}

struct TeamMessagesUnreadCountResponse: Codable {
    let count: Int
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

struct PaginationMeta: Codable, Equatable {
    let limit: Int
    let offset: Int
    let returned: Int

    init(limit: Int, offset: Int, returned: Int) {
        self.limit = limit
        self.offset = offset
        self.returned = returned
    }
}

struct PaginatedResponse<T: Decodable>: Decodable {
    let items: [T]
    let pagination: PaginationMeta

    private enum CodingKeys: String, CodingKey {
        case items
        case pagination
    }

    init(items: [T], pagination: PaginationMeta) {
        self.items = items
        self.pagination = pagination
    }

    init(from decoder: Decoder) throws {
        if var arrayContainer = try? decoder.unkeyedContainer() {
            var items: [T] = []
            while !arrayContainer.isAtEnd {
                items.append(try arrayContainer.decode(T.self))
            }
            self.items = items
            self.pagination = PaginationMeta(limit: items.count, offset: 0, returned: items.count)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedItems = try container.decode([T].self, forKey: .items)
        let decodedPagination = (try? container.decode(PaginationMeta.self, forKey: .pagination))
            ?? PaginationMeta(limit: decodedItems.count, offset: 0, returned: decodedItems.count)

        self.items = decodedItems
        self.pagination = decodedPagination
    }
}

struct Coach: Codable, Identifiable {
    let id: String
    let email: String?
    let firstName: String?
    let lastName: String?
    let managedTeamIds: [String]?
}

struct Player: Decodable, Identifiable {
    struct ParentContact: Decodable, Identifiable {
        let parentId: String?
        let parentUserId: String?
        let firstName: String?
        let lastName: String?
        let email: String?
        let phone: String?
        let status: String?

        var id: String {
            parentId ?? [firstName ?? "", lastName ?? "", email ?? "", phone ?? ""].joined(separator: "|")
        }
    }

    let id: String
    let name: String
    let firstName: String?
    let lastName: String?
    let primaryPosition: String?
    let secondaryPosition: String?
    let email: String?
    let phone: String?
    let isChild: Bool
    let parentContacts: [ParentContact]
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
        case isChild
        case is_child
        case enfant
        case parentContacts
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
        isChild = (try? container.decodeIfPresent(Bool.self, forKey: .isChild))
            ?? (try? container.decodeIfPresent(Bool.self, forKey: .is_child))
            ?? (try? container.decodeIfPresent(Bool.self, forKey: .enfant))
            ?? false
        parentContacts = (try? container.decodeIfPresent([ParentContact].self, forKey: .parentContacts)) ?? []
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
        isChild: Bool = false,
        parentContacts: [ParentContact] = [],
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
        self.isChild = isChild
        self.parentContacts = parentContacts
        self.teamId = teamId
    }
}

struct PlayerInvitationStatusResponse: Decodable {
    let playerId: String
    let status: String
    let lastInvitationAt: String?
    let invitationId: String?
}

struct PlayerInviteResponse: Decodable {
    let status: String
    let invitationId: String?
    let sentAt: String?
    let expiresAt: String?
    let inviteUrl: String?
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
    let pagination: PaginationMeta

    enum CodingKeys: String, CodingKey {
        case items
        case categories
        case tags
        case pagination
    }

    init(items: [Drill], categories: [String], tags: [String], pagination: PaginationMeta) {
        self.items = items
        self.categories = categories
        self.tags = tags
        self.pagination = pagination
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let items = (try? container.decode([Drill].self, forKey: .items)) ?? []
        self.items = items
        self.categories = (try? container.decode([String].self, forKey: .categories)) ?? []
        self.tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        self.pagination = (try? container.decode(PaginationMeta.self, forKey: .pagination))
            ?? PaginationMeta(limit: items.count, offset: 0, returned: items.count)
    }
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

struct TrainingAttendanceResponse: Decodable {
    let items: [AttendanceRow]
}

struct TrainingDrill: Decodable, Identifiable {
    let id: String
    let trainingId: String?
    let drillId: String
    let order: Int

    init(id: String, trainingId: String?, drillId: String, order: Int) {
        self.id = id
        self.trainingId = trainingId
        self.drillId = drillId
        self.order = order
    }

    enum CodingKeys: String, CodingKey {
        case id
        case trainingId
        case training_id
        case drillId
        case drill_id
        case order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        trainingId = (try? container.decodeIfPresent(String.self, forKey: .trainingId))
            ?? (try? container.decodeIfPresent(String.self, forKey: .training_id))
        if let modernDrillID = try? container.decode(String.self, forKey: .drillId) {
            drillId = modernDrillID
        } else {
            drillId = try container.decode(String.self, forKey: .drill_id)
        }
        order = (try? container.decode(Int.self, forKey: .order)) ?? 0
    }
}

struct TrainingRoleAssignment: Decodable, Identifiable {
    let id: String
    let trainingId: String?
    let role: String
    let playerId: String

    enum CodingKeys: String, CodingKey {
        case id
        case trainingId
        case training_id
        case role
        case playerId
        case player_id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        trainingId = (try? container.decodeIfPresent(String.self, forKey: .trainingId))
            ?? (try? container.decodeIfPresent(String.self, forKey: .training_id))
        role = try container.decode(String.self, forKey: .role)
        if let modernPlayerID = try? container.decode(String.self, forKey: .playerId) {
            playerId = modernPlayerID
        } else {
            playerId = try container.decode(String.self, forKey: .player_id)
        }
    }
}

struct TrainingRolesResponse: Decodable {
    let items: [TrainingRoleAssignment]
}

struct MatchScorer: Decodable, Identifiable {
    let id: String?
    let playerId: String
    let side: String
    let playerName: String?
    let assistId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case playerId
        case player_id
        case side
        case playerName
        case player_name
        case assistId
        case assist_id
    }

    init(id: String? = nil, playerId: String, side: String, playerName: String? = nil, assistId: String? = nil) {
        self.id = id
        self.playerId = playerId
        self.side = side
        self.playerName = playerName
        self.assistId = assistId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        if let modernPlayerID = try? container.decode(String.self, forKey: .playerId) {
            playerId = modernPlayerID
        } else {
            playerId = try container.decode(String.self, forKey: .player_id)
        }
        side = (try? container.decode(String.self, forKey: .side)) ?? "home"
        playerName = (try? container.decodeIfPresent(String.self, forKey: .playerName))
            ?? (try? container.decodeIfPresent(String.self, forKey: .player_name))
        assistId = (try? container.decodeIfPresent(String.self, forKey: .assistId))
            ?? (try? container.decodeIfPresent(String.self, forKey: .assist_id))
    }
}

struct MatchTeamLite: Codable, Identifiable {
    let id: String
    let side: String
    let score: Int
}

struct MatchLite: Decodable, Identifiable {
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
    let startTime: String?
    let terrain: String?
    let field: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case created_at
        case type
        case matchdayId
        case matchday_id
        case rotationGameKey
        case rotation_game_key
        case status
        case played
        case teams
        case scorers
        case opponentName
        case opponent_name
        case startTime
        case start_time
        case terrain
        case field
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = (try? container.decode(String.self, forKey: .createdAt))
            ?? (try? container.decode(String.self, forKey: .created_at))
            ?? ""
        type = try container.decode(String.self, forKey: .type)
        matchdayId = (try? container.decodeIfPresent(String.self, forKey: .matchdayId))
            ?? (try? container.decodeIfPresent(String.self, forKey: .matchday_id))
        rotationGameKey = (try? container.decodeIfPresent(String.self, forKey: .rotationGameKey))
            ?? (try? container.decodeIfPresent(String.self, forKey: .rotation_game_key))
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        played = try? container.decodeIfPresent(Bool.self, forKey: .played)
        teams = (try? container.decode([MatchTeamLite].self, forKey: .teams)) ?? []
        scorers = (try? container.decode([MatchScorer].self, forKey: .scorers)) ?? []
        opponentName = (try? container.decodeIfPresent(String.self, forKey: .opponentName))
            ?? (try? container.decodeIfPresent(String.self, forKey: .opponent_name))
        startTime = (try? container.decodeIfPresent(String.self, forKey: .startTime))
            ?? (try? container.decodeIfPresent(String.self, forKey: .start_time))
        terrain = try? container.decodeIfPresent(String.self, forKey: .terrain)
        field = try? container.decodeIfPresent(String.self, forKey: .field)
    }
}

struct MatchdaySummary: Decodable {
    let mode: String?
    let matches: [MatchLite]?
    let rotation: MatchdayRotationSummary?
    let convocations: [MatchdayConvocation]?
}

struct MatchdayConvocation: Decodable, Identifiable {
    let id: String
    let playerId: String
    let status: String
    let playerName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case playerId
        case player_id
        case status
        case playerName
        case player_name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPlayerId = (try? container.decodeIfPresent(String.self, forKey: .playerId))
            ?? (try? container.decodeIfPresent(String.self, forKey: .player_id))
            ?? ""
        playerId = rawPlayerId
        status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? ""
        playerName = (try? container.decodeIfPresent(String.self, forKey: .playerName))
            ?? (try? container.decodeIfPresent(String.self, forKey: .player_name))
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? rawPlayerId
    }
}

struct MatchDetail: Decodable, Identifiable {
    let id: String
    let type: String
    let matchdayId: String?
    let opponentName: String?
    let played: Bool?
    let status: String?
    let rotationGameKey: String?
    let teams: [MatchDetailTeam]
    let scorers: [MatchScorer]
    let tactic: MatchTactic?
    let startTime: String?
    let terrain: String?
    let field: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case matchdayId
        case matchday_id
        case opponentName
        case opponent_name
        case played
        case status
        case rotationGameKey
        case rotation_game_key
        case teams
        case scorers
        case tactic
        case tactical
        case tactique
        case startTime
        case start_time
        case terrain
        case field
    }

    init(
        id: String,
        type: String,
        matchdayId: String?,
        opponentName: String?,
        played: Bool?,
        status: String?,
        rotationGameKey: String?,
        teams: [MatchDetailTeam],
        scorers: [MatchScorer],
        tactic: MatchTactic?,
        startTime: String?,
        terrain: String?,
        field: String?
    ) {
        self.id = id
        self.type = type
        self.matchdayId = matchdayId
        self.opponentName = opponentName
        self.played = played
        self.status = status
        self.rotationGameKey = rotationGameKey
        self.teams = teams
        self.scorers = scorers
        self.tactic = tactic
        self.startTime = startTime
        self.terrain = terrain
        self.field = field
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = (try? container.decode(String.self, forKey: .type)) ?? "PLATEAU"
        matchdayId = (try? container.decodeIfPresent(String.self, forKey: .matchdayId))
            ?? (try? container.decodeIfPresent(String.self, forKey: .matchday_id))
        opponentName = (try? container.decodeIfPresent(String.self, forKey: .opponentName))
            ?? (try? container.decodeIfPresent(String.self, forKey: .opponent_name))
        played = try? container.decodeIfPresent(Bool.self, forKey: .played)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        rotationGameKey = (try? container.decodeIfPresent(String.self, forKey: .rotationGameKey))
            ?? (try? container.decodeIfPresent(String.self, forKey: .rotation_game_key))
        teams = (try? container.decode([MatchDetailTeam].self, forKey: .teams)) ?? []
        scorers = (try? container.decode([MatchScorer].self, forKey: .scorers)) ?? []
        tactic = (try? container.decodeIfPresent(MatchTactic.self, forKey: .tactic))
            ?? (try? container.decodeIfPresent(MatchTactic.self, forKey: .tactical))
            ?? (try? container.decodeIfPresent(MatchTactic.self, forKey: .tactique))
        startTime = (try? container.decodeIfPresent(String.self, forKey: .startTime))
            ?? (try? container.decodeIfPresent(String.self, forKey: .start_time))
        terrain = try? container.decodeIfPresent(String.self, forKey: .terrain)
        field = try? container.decodeIfPresent(String.self, forKey: .field)
    }
}

struct MatchDetailTeam: Decodable, Identifiable {
    let id: String
    let side: String
    let score: Int
    let players: [MatchDetailTeamPlayer]

    enum CodingKeys: String, CodingKey {
        case id
        case side
        case score
        case players
    }

    init(id: String, side: String, score: Int, players: [MatchDetailTeamPlayer]) {
        self.id = id
        self.side = side
        self.score = score
        self.players = players
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        side = (try? container.decode(String.self, forKey: .side)) ?? "home"
        score = (try? container.decode(Int.self, forKey: .score)) ?? 0
        players = (try? container.decode([MatchDetailTeamPlayer].self, forKey: .players)) ?? []
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? side
    }
}

struct MatchDetailTeamPlayer: Decodable, Identifiable, Hashable {
    let id: String
    let playerId: String
    let role: String
    let playerName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case playerId
        case player_id
        case role
        case playerName
        case player_name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPlayerId = (try? container.decodeIfPresent(String.self, forKey: .playerId))
            ?? (try? container.decodeIfPresent(String.self, forKey: .player_id))
            ?? ""
        playerId = rawPlayerId
        role = (try? container.decodeIfPresent(String.self, forKey: .role)) ?? ""
        playerName = (try? container.decodeIfPresent(String.self, forKey: .playerName))
            ?? (try? container.decodeIfPresent(String.self, forKey: .player_name))
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? rawPlayerId
    }
}

struct MatchTactic: Codable, Equatable {
    let preset: String?
    let points: [String: MatchTacticPoint]
}

struct MatchTacticPoint: Codable, Equatable {
    let x: Double
    let y: Double
}

struct MatchdayRotationSummary: Decodable {
    let updatedAt: String?
    let start: String?
    let teams: [MatchdayRotationTeam]
    let slots: [MatchdayRotationSlot]

    enum CodingKeys: String, CodingKey {
        case updatedAt
        case start
        case teams
        case slots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
        start = try? container.decodeIfPresent(String.self, forKey: .start)
        teams = (try? container.decode([MatchdayRotationTeam].self, forKey: .teams)) ?? []
        slots = (try? container.decode([MatchdayRotationSlot].self, forKey: .slots)) ?? []
    }
}

struct MatchdayRotationTeam: Decodable, Identifiable {
    let id: String
    let label: String
    let color: String?
    let absent: Bool

    enum CodingKeys: String, CodingKey {
        case label
        case color
        case absent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        color = try? container.decodeIfPresent(String.self, forKey: .color)
        absent = (try? container.decode(Bool.self, forKey: .absent)) ?? false
        id = label
    }
}

struct MatchdayRotationSlot: Decodable, Identifiable {
    let id: String
    let pitch: String?
    let time: String?
    let games: [MatchdayRotationGame]

    init(id: String, pitch: String?, time: String?, games: [MatchdayRotationGame]) {
        self.id = id
        self.pitch = pitch
        self.time = time
        self.games = games
    }

    enum CodingKeys: String, CodingKey {
        case id
        case pitch
        case time
        case games
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPitch = try? container.decodeIfPresent(String.self, forKey: .pitch)
        let rawTime = try? container.decodeIfPresent(String.self, forKey: .time)
        let decodedGames = (try? container.decode([MatchdayRotationGame].self, forKey: .games)) ?? []

        pitch = rawPitch
        time = rawTime
        games = decodedGames
        id = (try? container.decodeIfPresent(String.self, forKey: .id))
            ?? "\(rawTime ?? "time")-\(rawPitch ?? "pitch")-\(decodedGames.map(\.id).joined(separator: "|"))"
    }
}

struct MatchdayRotationGame: Decodable, Identifiable {
    let id: String
    let key: String?
    let teamA: String?
    let teamB: String?
    let pitch: String?
    let time: String?

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case rotationGameKey
        case rotation_game_key
        case teamA
        case team_a
        case a = "A"
        case teamB
        case team_b
        case b = "B"
        case pitch
        case time
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = try? container.decodeIfPresent(String.self, forKey: .id)
        let rawKey = (try? container.decodeIfPresent(String.self, forKey: .key))
            ?? (try? container.decodeIfPresent(String.self, forKey: .rotationGameKey))
            ?? (try? container.decodeIfPresent(String.self, forKey: .rotation_game_key))
        let rawTeamA = (try? container.decodeIfPresent(String.self, forKey: .teamA))
            ?? (try? container.decodeIfPresent(String.self, forKey: .team_a))
            ?? (try? container.decodeIfPresent(String.self, forKey: .a))
        let rawTeamB = (try? container.decodeIfPresent(String.self, forKey: .teamB))
            ?? (try? container.decodeIfPresent(String.self, forKey: .team_b))
            ?? (try? container.decodeIfPresent(String.self, forKey: .b))

        id = rawID ?? rawKey ?? UUID().uuidString
        key = rawKey
        teamA = rawTeamA
        teamB = rawTeamB
        pitch = try? container.decodeIfPresent(String.self, forKey: .pitch)
        time = try? container.decodeIfPresent(String.self, forKey: .time)
    }
}

struct Planning: Decodable, Identifiable {
    let id: String
    let date: String
    let data: PlanningData?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case data
        case createdAt
        case created_at
        case updatedAt
        case updated_at
    }

    init(id: String, date: String, data: PlanningData?, createdAt: String?, updatedAt: String?) {
        self.id = id
        self.date = date
        self.data = data
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = (try? container.decode(String.self, forKey: .date)) ?? ""
        data = try? container.decodeIfPresent(PlanningData.self, forKey: .data)
        createdAt = (try? container.decodeIfPresent(String.self, forKey: .createdAt))
            ?? (try? container.decodeIfPresent(String.self, forKey: .created_at))
        updatedAt = (try? container.decodeIfPresent(String.self, forKey: .updatedAt))
            ?? (try? container.decodeIfPresent(String.self, forKey: .updated_at))
    }
}

struct PlanningData: Codable {
    var start: String
    var pitches: Int
    var matchMin: Int
    var breakMin: Int
    var forbidIntraClub: Bool?
    var matchesPerTeam: Int?
    var restEveryX: Int?
    var allowRematches: Bool?
    var regenSeed: Int?
    var teams: [PlanningTeam]
    var slots: [PlanningSlot]
}

struct PlanningTeam: Codable, Identifiable, Hashable {
    var id: String { label }
    var label: String
    var color: String
}

struct PlanningSlot: Codable, Identifiable, Hashable {
    var id: String { "\(time)-\(games.map { "\($0.pitch)-\($0.a)-\($0.b)" }.joined(separator: "|"))" }
    var time: String
    var games: [PlanningGame]
}

struct PlanningGame: Codable, Identifiable, Hashable {
    var id: String { "\(pitch)-\(a)-\(b)" }
    var pitch: Int
    var a: String
    var b: String

    enum CodingKeys: String, CodingKey {
        case pitch
        case a = "A"
        case b = "B"
    }
}

struct MatchPayload: Encodable {
    let type: String
    let matchdayId: String
    let sides: MatchSidesPayload
    let score: MatchScorePayload
    let buteurs: [MatchScorerPayload]
    let opponentName: String
    let played: Bool
    let rotationGameKey: String?
    let tactic: MatchTacticPayload?
}

struct MatchSidesPayload: Encodable {
    let home: MatchSidePlayersPayload
    let away: MatchSidePlayersPayload

    static let empty = MatchSidesPayload(
        home: MatchSidePlayersPayload(starters: [], subs: []),
        away: MatchSidePlayersPayload(starters: [], subs: [])
    )
}

struct MatchSidePlayersPayload: Encodable {
    let starters: [String]
    let subs: [String]
}

struct MatchScorePayload: Encodable {
    let home: Int
    let away: Int
}

struct MatchScorerPayload: Encodable, Hashable, Identifiable {
    var id: String { "\(playerId)-\(side)" }
    let playerId: String
    let side: String
    let assistId: String?

    init(playerId: String, side: String, assistId: String? = nil) {
        self.playerId = playerId
        self.side = side
        self.assistId = assistId
    }
}

struct MatchTacticPayload: Encodable {
    let preset: String?
    let points: [String: MatchTacticPointPayload]
}

struct MatchTacticPointPayload: Encodable {
    let x: Double
    let y: Double
}
