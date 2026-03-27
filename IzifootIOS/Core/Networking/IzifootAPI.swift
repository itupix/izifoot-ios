import Foundation

struct AuthResponse: Codable {
    let token: String?
    let user: Me?
    let me: Me?
    let id: String?
    let email: String?
    let isPremium: Bool?
    let planningCount: Int?
    let role: AccountRole?
    let clubId: String?
    let teamId: String?
    let managedTeamIds: [String]?
    let linkedPlayerUserId: String?

    var normalizedMe: Me? {
        if let user { return user }
        if let me { return me }
        guard let id, let email, let role else { return nil }
        return Me(
            id: id,
            email: email,
            isPremium: isPremium ?? false,
            planningCount: planningCount,
            role: role,
            clubId: clubId,
            teamId: teamId,
            managedTeamIds: managedTeamIds ?? [],
            linkedPlayerUserId: linkedPlayerUserId
        )
    }
}

struct EmptyResponse: Codable {
    let ok: Bool?
}

struct ShareResponse: Codable {
    let token: String
    let url: String
    let expiresAt: String?
}

final class IzifootAPI {
    private let client: APIClientProtocol

    init(client: APIClientProtocol = APIClient.shared) {
        self.client = client
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await client.post(
            APIRoutes.Auth.login,
            body: ["email": email, "password": password],
            responseType: AuthResponse.self
        )
    }

    func register(email: String, password: String, clubName: String) async throws -> AuthResponse {
        try await client.post(
            APIRoutes.Auth.register,
            body: ["email": email, "password": password, "clubName": clubName, "club": clubName],
            responseType: AuthResponse.self
        )
    }

    func logout() async throws {
        _ = try await client.post(APIRoutes.Auth.logout, body: [String: String](), responseType: EmptyResponse.self)
    }

    func me() async throws -> Me {
        try await client.get(APIRoutes.me, responseType: Me.self)
    }

    func myClub() async throws -> Club {
        try await client.get(APIRoutes.Clubs.me, responseType: Club.self)
    }

    func teams() async throws -> [Team] {
        try await client.get(APIRoutes.Teams.list, responseType: [Team].self)
    }

    func createTeam(name: String, category: String?, format: String?) async throws -> Team {
        struct CreateTeamPayload: Encodable {
            let name: String
            let category: String?
            let format: String?
        }
        return try await client.post(
            APIRoutes.Teams.list,
            body: CreateTeamPayload(name: name, category: category, format: format),
            responseType: Team.self
        )
    }

    func clubCoaches() async throws -> [Coach] {
        try await client.get(APIRoutes.Clubs.coaches, responseType: [Coach].self)
    }

    func players() async throws -> [Player] {
        try await client.get(APIRoutes.Players.list, responseType: [Player].self)
    }

    func player(id: String) async throws -> Player {
        try await client.get(APIRoutes.Players.byID(id), responseType: Player.self)
    }

    func createPlayer(
        firstName: String,
        lastName: String,
        email: String,
        phone: String,
        primaryPosition: String,
        secondaryPosition: String?
    ) async throws -> Player {
        struct CreatePlayerPayload: Encodable {
            let prenom: String
            let nom: String
            let email: String
            let phone: String
            let primary_position: String
            let secondary_position: String?
        }

        return try await client.post(
            APIRoutes.Players.list,
            body: CreatePlayerPayload(
                prenom: firstName,
                nom: lastName,
                email: email,
                phone: phone,
                primary_position: primaryPosition,
                secondary_position: secondaryPosition
            ),
            responseType: Player.self
        )
    }

    func trainings() async throws -> [Training] {
        try await client.get(APIRoutes.Trainings.list, responseType: [Training].self)
    }

    func createTraining(dateISO8601: String, status: String = "PLANIFIED") async throws -> Training {
        struct CreateTrainingPayload: Encodable {
            let date: String
            let status: String
        }
        return try await client.post(
            APIRoutes.Trainings.list,
            body: CreateTrainingPayload(date: dateISO8601, status: status),
            responseType: Training.self
        )
    }

    func matchdays() async throws -> [Matchday] {
        try await client.get(APIRoutes.Matchday.list, responseType: [Matchday].self)
    }

    func createMatchday(
        dateISO8601: String,
        lieu: String,
        startTime: String?,
        meetingTime: String?
    ) async throws -> Matchday {
        struct CreateMatchdayPayload: Encodable {
            let date: String
            let lieu: String
            let startTime: String?
            let meetingTime: String?
        }

        return try await client.post(
            APIRoutes.Matchday.list,
            body: CreateMatchdayPayload(
                date: dateISO8601,
                lieu: lieu,
                startTime: startTime,
                meetingTime: meetingTime
            ),
            responseType: Matchday.self
        )
    }

    func matches(matchdayID: String? = nil) async throws -> [MatchLite] {
        let path = matchdayID.map(APIRoutes.Matches.byMatchday) ?? APIRoutes.Matches.list
        return try await client.get(path, responseType: [MatchLite].self)
    }

    func drills() async throws -> DrillsResponse {
        try await client.get(APIRoutes.Drills.list, responseType: DrillsResponse.self)
    }

    func drill(id: String) async throws -> Drill {
        try await client.get(APIRoutes.Drills.byID(id), responseType: Drill.self)
    }

    func createDrill(
        title: String,
        category: String,
        duration: Int,
        players: String,
        description: String,
        tags: [String]
    ) async throws -> Drill {
        struct CreateDrillPayload: Encodable {
            let title: String
            let category: String
            let duration: Int
            let players: String
            let description: String
            let tags: [String]
        }

        return try await client.post(
            APIRoutes.Drills.list,
            body: CreateDrillPayload(
                title: title,
                category: category,
                duration: duration,
                players: players,
                description: description,
                tags: tags
            ),
            responseType: Drill.self
        )
    }

    func attendanceBySession(type: String, sessionID: String) async throws -> [AttendanceRow] {
        try await client.get(APIRoutes.Attendance.bySession(type: type, sessionID: sessionID), responseType: [AttendanceRow].self)
    }

    func shareMatchday(id: String) async throws -> ShareResponse {
        try await client.post(APIRoutes.Matchday.share(id), body: [String: String](), responseType: ShareResponse.self)
    }

    func publicMatchday(token: String) async throws -> Matchday {
        try await client.get(APIRoutes.Public.matchdayByToken(token), responseType: Matchday.self)
    }
}
