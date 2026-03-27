import Foundation

struct AuthResponse: Codable {
    let token: String?
    let user: Me?
    let me: Me?
    let id: String?
    let email: String?
    let firstName: String?
    let lastName: String?
    let phone: String?
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
            firstName: firstName,
            lastName: lastName,
            phone: phone,
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

    init(ok: Bool? = nil) {
        self.ok = ok
    }
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

    private func paginatedPath(_ path: String, limit: Int, offset: Int, extraQueryItems: [URLQueryItem] = []) -> String {
        guard var components = URLComponents(string: path) else {
            return path
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(contentsOf: extraQueryItems)
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        components.queryItems = queryItems
        return components.string ?? path
    }

    private func appendQueryItems(_ path: String, items: [URLQueryItem]) -> String {
        guard var components = URLComponents(string: path) else {
            return path
        }
        components.queryItems = (components.queryItems ?? []) + items
        return components.string ?? path
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

    func updateMeProfile(firstName: String, lastName: String, email: String, phone: String) async throws -> Me {
        struct UpdateProfilePayload: Encodable {
            let firstName: String
            let lastName: String
            let email: String
            let phone: String
        }

        return try await client.put(
            APIRoutes.meProfile,
            body: UpdateProfilePayload(firstName: firstName, lastName: lastName, email: email, phone: phone),
            responseType: Me.self
        )
    }

    func myClub() async throws -> Club {
        try await client.get(APIRoutes.Clubs.me, responseType: Club.self)
    }

    func renameClub(name: String) async throws -> Club {
        struct RenameClubPayload: Encodable {
            let name: String
        }

        return try await client.put(
            APIRoutes.Clubs.me,
            body: RenameClubPayload(name: name),
            responseType: Club.self
        )
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

    func players(limit: Int = 50, offset: Int = 0) async throws -> PaginatedResponse<Player> {
        try await client.get(
            paginatedPath(APIRoutes.Players.list, limit: limit, offset: offset),
            responseType: PaginatedResponse<Player>.self
        )
    }

    func allPlayers(pageSize: Int = 100) async throws -> [Player] {
        var allItems: [Player] = []
        var offset = 0

        while true {
            let response = try await players(limit: pageSize, offset: offset)
            allItems.append(contentsOf: response.items)
            guard response.pagination.returned >= response.pagination.limit, response.pagination.returned > 0 else { break }
            offset += response.pagination.returned
        }

        return allItems
    }

    func player(id: String) async throws -> Player {
        try await client.get(APIRoutes.Players.byID(id), responseType: Player.self)
    }

    func playerInvitationStatus(id: String) async throws -> PlayerInvitationStatusResponse {
        try await client.get(APIRoutes.Players.invitationStatus(id), responseType: PlayerInvitationStatusResponse.self)
    }

    func invitePlayer(id: String) async throws -> PlayerInviteResponse {
        struct EmptyPayload: Encodable {}
        return try await client.post(
            APIRoutes.Players.invite(id),
            body: EmptyPayload(),
            responseType: PlayerInviteResponse.self
        )
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

    func trainings(limit: Int = 50, offset: Int = 0) async throws -> PaginatedResponse<Training> {
        try await client.get(
            paginatedPath(APIRoutes.Trainings.list, limit: limit, offset: offset),
            responseType: PaginatedResponse<Training>.self
        )
    }

    func allTrainings(pageSize: Int = 100) async throws -> [Training] {
        var allItems: [Training] = []
        var offset = 0

        while true {
            let response = try await trainings(limit: pageSize, offset: offset)
            allItems.append(contentsOf: response.items)
            guard response.pagination.returned >= response.pagination.limit, response.pagination.returned > 0 else { break }
            offset += response.pagination.returned
        }

        return allItems
    }

    func createTraining(
        dateISO8601: String,
        status: String = "PLANIFIED",
        teamID: String? = nil,
        teamName: String? = nil
    ) async throws -> Training {
        struct CreateTrainingPayload: Encodable {
            let date: String
            let status: String
            let teamId: String?
            let team_id: String?
            let teamName: String?
            let activeTeamId: String?
            let active_team_id: String?
        }
        return try await client.post(
            APIRoutes.Trainings.list,
            body: CreateTrainingPayload(
                date: dateISO8601,
                status: status,
                teamId: teamID,
                team_id: teamID,
                teamName: teamName,
                activeTeamId: teamID,
                active_team_id: teamID
            ),
            responseType: Training.self
        )
    }

    func matchdays(limit: Int = 50, offset: Int = 0) async throws -> PaginatedResponse<Matchday> {
        try await client.get(
            paginatedPath(APIRoutes.Matchday.list, limit: limit, offset: offset),
            responseType: PaginatedResponse<Matchday>.self
        )
    }

    func allMatchdays(pageSize: Int = 100) async throws -> [Matchday] {
        var allItems: [Matchday] = []
        var offset = 0

        while true {
            let response = try await matchdays(limit: pageSize, offset: offset)
            allItems.append(contentsOf: response.items)
            guard response.pagination.returned >= response.pagination.limit, response.pagination.returned > 0 else { break }
            offset += response.pagination.returned
        }

        return allItems
    }

    func createMatchday(
        dateISO8601: String,
        lieu: String,
        teamID: String? = nil,
        teamName: String? = nil,
        startTime: String?,
        meetingTime: String?
    ) async throws -> Matchday {
        struct CreateMatchdayPayload: Encodable {
            let date: String
            let lieu: String
            let teamId: String?
            let team_id: String?
            let teamName: String?
            let activeTeamId: String?
            let active_team_id: String?
            let startTime: String?
            let meetingTime: String?
        }

        return try await client.post(
            APIRoutes.Matchday.list,
            body: CreateMatchdayPayload(
                date: dateISO8601,
                lieu: lieu,
                teamId: teamID,
                team_id: teamID,
                teamName: teamName,
                activeTeamId: teamID,
                active_team_id: teamID,
                startTime: startTime,
                meetingTime: meetingTime
            ),
            responseType: Matchday.self
        )
    }

    func deleteMatchday(id: String) async throws {
        _ = try await client.delete(
            APIRoutes.Matchday.byID(id),
            responseType: EmptyResponse.self
        )
    }

    func matches(matchdayID: String? = nil, limit: Int = 50, offset: Int = 0) async throws -> PaginatedResponse<MatchLite> {
        let path = paginatedPath(
            APIRoutes.Matches.list,
            limit: limit,
            offset: offset,
            extraQueryItems: matchdayID.map { [URLQueryItem(name: "matchdayId", value: $0)] } ?? []
        )
        return try await client.get(path, responseType: PaginatedResponse<MatchLite>.self)
    }

    func allMatches(matchdayID: String? = nil, pageSize: Int = 100) async throws -> [MatchLite] {
        var allItems: [MatchLite] = []
        var offset = 0

        while true {
            let response = try await matches(matchdayID: matchdayID, limit: pageSize, offset: offset)
            allItems.append(contentsOf: response.items)
            guard response.pagination.returned >= response.pagination.limit, response.pagination.returned > 0 else { break }
            offset += response.pagination.returned
        }

        return allItems
    }

    func match(id: String) async throws -> MatchDetail {
        try await client.get(APIRoutes.Matches.byID(id), responseType: MatchDetail.self)
    }

    func matchdaySummary(id: String, includeAllPlayers: Bool = false) async throws -> MatchdaySummary {
        let path = includeAllPlayers
            ? appendQueryItems(APIRoutes.Matchday.summary(id), items: [URLQueryItem(name: "includeAllPlayers", value: "true")])
            : APIRoutes.Matchday.summary(id)
        return try await client.get(path, responseType: MatchdaySummary.self)
    }

    func setMatchdayTeamAbsence(id: String, teamLabel: String, absent: Bool) async throws {
        struct TeamAbsencePayload: Encodable {
            let teamLabel: String
            let absent: Bool
        }

        _ = try await client.post(
            APIRoutes.Matchday.teamsAbsence(id),
            body: TeamAbsencePayload(teamLabel: teamLabel, absent: absent),
            responseType: EmptyResponse.self
        )
    }

    func plannings() async throws -> [Planning] {
        try await client.get(APIRoutes.Plannings.list, responseType: [Planning].self)
    }

    func createPlanning(dateISO: String, data: PlanningData) async throws -> Planning {
        struct CreatePlanningPayload: Encodable {
            let date: String
            let data: PlanningData
        }

        return try await client.post(
            APIRoutes.Plannings.list,
            body: CreatePlanningPayload(date: dateISO, data: data),
            responseType: Planning.self
        )
    }

    func updatePlanning(id: String, data: PlanningData) async throws -> Planning {
        struct UpdatePlanningPayload: Encodable {
            let data: PlanningData
        }

        struct UpdatePlanningResponse: Decodable {
            let updated: Planning
            let data: PlanningData?
        }

        let response = try await client.put(
            APIRoutes.Plannings.byID(id),
            body: UpdatePlanningPayload(data: data),
            responseType: UpdatePlanningResponse.self
        )

        return Planning(
            id: response.updated.id,
            date: response.updated.date,
            data: response.data ?? response.updated.data,
            createdAt: response.updated.createdAt,
            updatedAt: response.updated.updatedAt
        )
    }

    func deletePlanning(id: String) async throws {
        _ = try await client.delete(
            APIRoutes.Plannings.byID(id),
            responseType: EmptyResponse.self
        )
    }

    func createMatch(payload: MatchPayload) async throws -> MatchLite {
        try await client.post(
            APIRoutes.Matches.list,
            body: payload,
            responseType: MatchLite.self
        )
    }

    func updateMatch(id: String, payload: MatchPayload) async throws -> MatchLite {
        try await client.put(
            APIRoutes.Matches.byID(id),
            body: payload,
            responseType: MatchLite.self
        )
    }

    func deleteMatch(id: String) async throws {
        _ = try await client.delete(
            APIRoutes.Matches.byID(id),
            responseType: EmptyResponse.self
        )
    }

    func trainingDrills(trainingID: String) async throws -> [TrainingDrill] {
        try await client.get(APIRoutes.Trainings.drills(trainingID), responseType: [TrainingDrill].self)
    }

    func addTrainingDrill(trainingID: String, drillID: String) async throws -> TrainingDrill {
        struct AddTrainingDrillPayload: Encodable {
            let drillId: String
            let drill_id: String
        }

        return try await client.post(
            APIRoutes.Trainings.drills(trainingID),
            body: AddTrainingDrillPayload(drillId: drillID, drill_id: drillID),
            responseType: TrainingDrill.self
        )
    }

    func updateTrainingDrillOrder(trainingID: String, trainingDrillID: String, order: Int) async throws -> TrainingDrill {
        struct UpdateTrainingDrillPayload: Encodable {
            let order: Int
        }

        return try await client.put(
            APIRoutes.Trainings.drillByID(trainingID, trainingDrillID: trainingDrillID),
            body: UpdateTrainingDrillPayload(order: order),
            responseType: TrainingDrill.self
        )
    }

    func deleteTrainingDrill(trainingID: String, trainingDrillID: String) async throws {
        _ = try await client.delete(
            APIRoutes.Trainings.drillByID(trainingID, trainingDrillID: trainingDrillID),
            responseType: EmptyResponse.self
        )
    }

    func trainingRoles(trainingID: String) async throws -> TrainingRolesResponse {
        try await client.get(APIRoutes.Trainings.roles(trainingID), responseType: TrainingRolesResponse.self)
    }

    func updateTrainingRoles(trainingID: String, items: [(role: String, playerID: String)]) async throws -> TrainingRolesResponse {
        struct RoleItemPayload: Encodable {
            let role: String
            let playerId: String
        }

        struct RolesPayload: Encodable {
            let items: [RoleItemPayload]
        }

        return try await client.put(
            APIRoutes.Trainings.roles(trainingID),
            body: RolesPayload(items: items.map { RoleItemPayload(role: $0.role, playerId: $0.playerID) }),
            responseType: TrainingRolesResponse.self
        )
    }

    func drills(limit: Int = 50, offset: Int = 0) async throws -> DrillsResponse {
        try await client.get(
            paginatedPath(APIRoutes.Drills.list, limit: limit, offset: offset),
            responseType: DrillsResponse.self
        )
    }

    func allDrills(pageSize: Int = 100) async throws -> DrillsResponse {
        var allItems: [Drill] = []
        var categories = Set<String>()
        var tags = Set<String>()
        var offset = 0

        while true {
            let response = try await drills(limit: pageSize, offset: offset)
            allItems.append(contentsOf: response.items)
            categories.formUnion(response.categories)
            tags.formUnion(response.tags)
            guard response.pagination.returned >= response.pagination.limit, response.pagination.returned > 0 else { break }
            offset += response.pagination.returned
        }

        return DrillsResponse(
            items: allItems,
            categories: categories.sorted(),
            tags: tags.sorted(),
            pagination: PaginationMeta(limit: allItems.count, offset: 0, returned: allItems.count)
        )
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

    func attendanceBySession(type: String, sessionID: String, limit: Int = 100, offset: Int = 0) async throws -> PaginatedResponse<AttendanceRow> {
        try await client.get(
            paginatedPath(APIRoutes.Attendance.bySession(type: type, sessionID: sessionID), limit: limit, offset: offset),
            responseType: PaginatedResponse<AttendanceRow>.self
        )
    }

    func attendance(limit: Int = 100, offset: Int = 0) async throws -> PaginatedResponse<AttendanceRow> {
        try await client.get(
            paginatedPath(APIRoutes.Attendance.list, limit: limit, offset: offset),
            responseType: PaginatedResponse<AttendanceRow>.self
        )
    }

    func allAttendance(pageSize: Int = 100) async throws -> [AttendanceRow] {
        var allItems: [AttendanceRow] = []
        var offset = 0

        while true {
            let response = try await attendance(limit: pageSize, offset: offset)
            allItems.append(contentsOf: response.items)
            guard response.pagination.returned >= response.pagination.limit, response.pagination.returned > 0 else { break }
            offset += response.pagination.returned
        }

        return allItems
    }

    func allAttendanceBySession(type: String, sessionID: String, pageSize: Int = 100) async throws -> [AttendanceRow] {
        var allItems: [AttendanceRow] = []
        var offset = 0

        while true {
            let response = try await attendanceBySession(type: type, sessionID: sessionID, limit: pageSize, offset: offset)
            allItems.append(contentsOf: response.items)
            guard response.pagination.returned >= response.pagination.limit, response.pagination.returned > 0 else { break }
            offset += response.pagination.returned
        }

        return allItems
    }

    func setAttendance(sessionType: String, sessionID: String, playerID: String, present: Bool) async throws {
        struct AttendancePayload: Encodable {
            let session_type: String
            let session_id: String
            let playerId: String
            let present: Bool
        }

        _ = try await client.post(
            APIRoutes.Attendance.list,
            body: AttendancePayload(
                session_type: sessionType,
                session_id: sessionID,
                playerId: playerID,
                present: present
            ),
            responseType: EmptyResponse.self
        )
    }

    func updateTrainingAttendance(trainingID: String, playerIDs: [String]) async throws -> [AttendanceRow] {
        struct TrainingAttendancePayload: Encodable {
            let playerIds: [String]
        }

        let response = try await client.put(
            APIRoutes.Trainings.attendance(trainingID),
            body: TrainingAttendancePayload(playerIds: playerIDs),
            responseType: TrainingAttendanceResponse.self
        )
        return response.items
    }

    func updateTraining(id: String, status: String) async throws -> Training {
        struct UpdateTrainingPayload: Encodable {
            let status: String
        }

        return try await client.put(
            APIRoutes.Trainings.byID(id),
            body: UpdateTrainingPayload(status: status),
            responseType: Training.self
        )
    }

    func deleteTraining(id: String) async throws {
        _ = try await client.delete(
            APIRoutes.Trainings.byID(id),
            responseType: EmptyResponse.self
        )
    }

    func updateMatchday(
        id: String,
        address: String? = nil,
        startTime: String? = nil,
        meetingTime: String? = nil
    ) async throws -> Matchday {
        struct UpdateMatchdayPayload: Encodable {
            let address: String?
            let startTime: String?
            let meetingTime: String?
        }

        return try await client.put(
            APIRoutes.Matchday.byID(id),
            body: UpdateMatchdayPayload(address: address, startTime: startTime, meetingTime: meetingTime),
            responseType: Matchday.self
        )
    }

    func shareMatchday(id: String) async throws -> ShareResponse {
        try await client.post(APIRoutes.Matchday.share(id), body: [String: String](), responseType: ShareResponse.self)
    }

    func publicMatchday(token: String) async throws -> Matchday {
        try await client.get(APIRoutes.Public.matchdayByToken(token), responseType: Matchday.self)
    }
}
