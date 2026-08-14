import Combine
import SwiftUI

@MainActor
final class PlayersHomeViewModel: ObservableObject {
    @Published private(set) var players: [Player] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?

    private let pageSize = 50
    private var nextOffset = 0
    private var canLoadMore = true
    private var isScopedToTeam = false

    private let api: IzifootAPI
    private var lastCacheKey: String?

    init(api: IzifootAPI? = nil) {
        self.api = api ?? IzifootAPI()
    }

    private struct CachedParentContact: Codable {
        let parentId: String?
        let parentUserId: String?
        let firstName: String?
        let lastName: String?
        let email: String?
        let phone: String?
        let status: String?
    }

    private struct CachedPlayer: Codable {
        let id: String
        let name: String
        let firstName: String?
        let lastName: String?
        let primaryPosition: String?
        let secondaryPosition: String?
        let licence: String?
        let dateOfBirth: String?
        let email: String?
        let phone: String?
        let isChild: Bool
        let parentContacts: [CachedParentContact]
        let teamId: String?
        let teamName: String?
        let isActive: Bool
        let deactivatedAt: String?
    }

    private struct PlayersHomeCachePayload: Codable {
        let players: [CachedPlayer]
        let nextOffset: Int
        let canLoadMore: Bool
    }

    var canLoadMorePlayers: Bool {
        !isScopedToTeam && canLoadMore && !isLoading && !isLoadingMore
    }

    func load(cacheKey: String, teamID: String? = nil, forceRefresh: Bool = false) async {
        if lastCacheKey != cacheKey {
            lastCacheKey = cacheKey
            players = []
            nextOffset = 0
            canLoadMore = true
            errorMessage = nil
        }

        let normalizedScopedTeamID = normalizedTeamID(teamID)
        isScopedToTeam = normalizedScopedTeamID != nil

        var hasCachedData = false
        if !forceRefresh,
           let cached = await PersistentDataCache.shared.read(PlayersHomeCachePayload.self, forKey: cacheKey) {
            players = filteredPlayers(
                cached.players.map { cached in
                    Player(
                        id: cached.id,
                        name: cached.name,
                        firstName: cached.firstName,
                        lastName: cached.lastName,
                        primaryPosition: cached.primaryPosition,
                        secondaryPosition: cached.secondaryPosition,
                        licence: cached.licence,
                        dateOfBirth: cached.dateOfBirth,
                        email: cached.email,
                        phone: cached.phone,
                        isChild: cached.isChild,
                        parentContacts: cached.parentContacts.map { contact in
                            Player.ParentContact(
                                parentId: contact.parentId,
                                parentUserId: contact.parentUserId,
                                firstName: contact.firstName,
                                lastName: contact.lastName,
                                email: contact.email,
                                phone: contact.phone,
                                status: contact.status
                            )
                        },
                        teamId: cached.teamId,
                        teamName: cached.teamName,
                        isActive: cached.isActive,
                        deactivatedAt: cached.deactivatedAt
                    )
                },
                teamID: normalizedScopedTeamID
            )
            nextOffset = cached.nextOffset
            canLoadMore = cached.canLoadMore && normalizedScopedTeamID == nil
            hasCachedData = true
            errorMessage = nil
        }

        do {
            if let normalizedScopedTeamID {
                let scopedPlayers = try await api.allPlayers(rosterStatus: .all)
                players = filteredPlayers(
                    scopedPlayers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
                    teamID: normalizedScopedTeamID
                )
                nextOffset = 0
                canLoadMore = false
            } else {
                let response = try await api.players(limit: pageSize, offset: 0, rosterStatus: .all)
                players = response.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                nextOffset = response.pagination.offset + response.pagination.returned
                canLoadMore = response.pagination.returned >= response.pagination.limit && response.pagination.returned > 0
            }
            await persistCache(forKey: cacheKey)
            errorMessage = nil
        } catch {
            if !error.isCancellationError, !hasCachedData { errorMessage = error.localizedDescription }
        }
    }

    func loadMore(cacheKey: String, teamID: String? = nil) async {
        guard normalizedTeamID(teamID) == nil else { return }
        guard canLoadMorePlayers else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await api.players(limit: pageSize, offset: nextOffset, rosterStatus: .all)
            players.append(contentsOf: response.items)
            players.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            nextOffset = response.pagination.offset + response.pagination.returned
            canLoadMore = response.pagination.returned >= response.pagination.limit && response.pagination.returned > 0
            await persistCache(forKey: cacheKey)
            errorMessage = nil
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    private func filteredPlayers(_ players: [Player], teamID: String?) -> [Player] {
        guard let teamID else { return players }
        return players.filter { player in
            normalizedTeamID(player.teamId) == teamID
        }
    }

    private func normalizedTeamID(_ teamID: String?) -> String? {
        guard let teamID = teamID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !teamID.isEmpty else {
            return nil
        }
        return teamID
    }

    func create(
        firstName: String,
        lastName: String?,
        primaryPosition: String?,
        secondaryPosition: String?,
        cacheKey: String
    ) async {
        do {
            let created = try await api.createPlayer(
                firstName: firstName,
                lastName: lastName,
                primaryPosition: primaryPosition,
                secondaryPosition: secondaryPosition
            )
            players.insert(created, at: 0)
            players.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            await persistCache(forKey: cacheKey)
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    private func persistCache(forKey cacheKey: String) async {
        await PersistentDataCache.shared.write(
            PlayersHomeCachePayload(
                players: players.map { player in
                    CachedPlayer(
                        id: player.id,
                        name: player.name,
                        firstName: player.firstName,
                        lastName: player.lastName,
                        primaryPosition: player.primaryPosition,
                        secondaryPosition: player.secondaryPosition,
                        licence: player.licence,
                        dateOfBirth: player.dateOfBirth,
                        email: player.email,
                        phone: player.phone,
                        isChild: player.isChild,
                        parentContacts: player.parentContacts.map { contact in
                            CachedParentContact(
                                parentId: contact.parentId,
                                parentUserId: contact.parentUserId,
                                firstName: contact.firstName,
                                lastName: contact.lastName,
                                email: contact.email,
                                phone: contact.phone,
                                status: contact.status
                            )
                        },
                        teamId: player.teamId,
                        teamName: player.teamName,
                        isActive: player.isActive,
                        deactivatedAt: player.deactivatedAt
                    )
                },
                nextOffset: nextOffset,
                canLoadMore: canLoadMore
            ),
            forKey: cacheKey
        )
    }
}

@MainActor
final class TeamStatsViewModel: ObservableObject {
    struct RankedStat: Identifiable {
        let id: String
        let name: String
        let value: Int
    }

    struct SeriesPoint: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
    }

    struct PlateauBand: Identifiable {
        let id = UUID()
        let index: Int
        let label: String
        let color: Color
    }

    @Published private(set) var isLoading = false
    @Published private(set) var playedMatchesCount = 0
    @Published private(set) var wins = 0
    @Published private(set) var draws = 0
    @Published private(set) var losses = 0
    @Published private(set) var totalFor = 0
    @Published private(set) var totalAgainst = 0
    @Published private(set) var avgForPerMatch: [SeriesPoint] = []
    @Published private(set) var avgAgainstPerMatch: [SeriesPoint] = []
    @Published private(set) var avgForPerPlateau: [SeriesPoint] = []
    @Published private(set) var avgAgainstPerPlateau: [SeriesPoint] = []
    @Published private(set) var plateauBands: [PlateauBand] = []
    @Published private(set) var scorers: [RankedStat] = []
    @Published private(set) var trainingPresence: [RankedStat] = []
    @Published private(set) var plateauPresence: [RankedStat] = []
    @Published private(set) var seasons: [Season] = []
    @Published var selectedSeasonID = ""
    @Published private(set) var seasonLabel = ""
    @Published private(set) var seasonRangeLabel = ""
    @Published var errorMessage: String?

    private let api: IzifootAPI
    private var loadedClub: Club?
    private var usesLocalSeasonFallback = false

    init(api: IzifootAPI? = nil) {
        self.api = api ?? IzifootAPI()
    }

    func load(players: [Player], teamID: String? = nil, refreshSeasonCatalog: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let normalizedScopedTeamID = normalizedTeamID(teamID)
            let shouldRefreshSeasonCatalog = refreshSeasonCatalog || seasons.isEmpty || loadedClub == nil
            let club: Club
            if shouldRefreshSeasonCatalog {
                club = try await api.myClub()
                loadedClub = club
            } else if let loadedClub {
                club = loadedClub
            } else {
                club = try await api.myClub()
                loadedClub = club
            }

            if shouldRefreshSeasonCatalog {
                do {
                    let fetchedSeasons = try await api.allClubSeasons()
                    usesLocalSeasonFallback = false
                    seasons = Self.mergedSeasons(fetchedSeasons, currentSeason: club.currentSeason)
                } catch {
                    if error.isMissingClubSeasonsEndpoint {
                        usesLocalSeasonFallback = true
                    } else {
                        throw error
                    }
                }
            }

            if usesLocalSeasonFallback {
                async let matchesTask = api.allMatches()
                async let attendanceTask = api.allAttendance()
                async let matchdaysTask = api.allMatchdays()
                async let trainingsTask = api.allTrainings()

                let matches = try await matchesTask
                let attendance = try await attendanceTask
                let matchdays = try await matchdaysTask
                let trainings = try await trainingsTask

                if shouldRefreshSeasonCatalog || seasons.isEmpty {
                    seasons = Self.fallbackSeasons(
                        club: club,
                        matches: matches,
                        matchdays: matchdays,
                        trainings: trainings
                    )
                }
                if selectedSeasonID.isEmpty || !seasons.contains(where: { $0.id == selectedSeasonID }) {
                    selectedSeasonID = club.currentSeason?.id ?? seasons.first?.id ?? ""
                }

                let selectedSeason = seasons.first(where: { $0.id == selectedSeasonID })
                seasonLabel = selectedSeason?.label ?? ""
                seasonRangeLabel = selectedSeason.map { SeasonSupport.rangeLabel(for: $0) } ?? ""

                let filteredTrainings = Self.filterTrainings(
                    trainings,
                    for: selectedSeason,
                    config: club.seasonConfig
                )
                let seasonMatchdays = Self.filterMatchdays(
                    matchdays,
                    for: selectedSeason,
                    config: club.seasonConfig
                )
                let seasonMatches = Self.filterMatches(
                    matches,
                    for: selectedSeason,
                    config: club.seasonConfig
                )
                let scopedTrainings = Self.filterByScope(
                    filteredTrainings,
                    teamID: \.teamId,
                    selectedTeamID: normalizedScopedTeamID
                )
                let scopedMatchdays = Self.filterByScope(
                    seasonMatchdays,
                    teamID: \.teamId,
                    selectedTeamID: normalizedScopedTeamID
                )
                let scopedMatches = Self.filterMatches(
                    seasonMatches,
                    matchdays: scopedMatchdays,
                    selectedTeamID: normalizedScopedTeamID
                )
                let scopedAttendance = Self.filterAttendance(
                    attendance,
                    playerIDs: Set(players.map(\.id)),
                    trainings: scopedTrainings,
                    matchdays: scopedMatchdays,
                    matches: scopedMatches
                )

                applyStats(
                    matches: scopedMatches,
                    attendance: scopedAttendance,
                    matchdays: scopedMatchdays,
                    players: players
                )
            } else {
                if selectedSeasonID.isEmpty || !seasons.contains(where: { $0.id == selectedSeasonID }) {
                    selectedSeasonID = club.currentSeason?.id ?? seasons.first?.id ?? ""
                }

                let selectedSeason = seasons.first(where: { $0.id == selectedSeasonID })
                seasonLabel = selectedSeason?.label ?? ""
                seasonRangeLabel = selectedSeason.map { SeasonSupport.rangeLabel(for: $0) } ?? ""
                let effectiveSeasonID = selectedSeason?.id

                async let matchesTask = api.allMatches(seasonID: effectiveSeasonID)
                async let attendanceTask = api.allAttendance(seasonID: effectiveSeasonID)
                async let matchdaysTask = api.allMatchdays(seasonID: effectiveSeasonID)
                async let trainingsTask = api.allTrainings(seasonID: effectiveSeasonID)

                let matches = try await matchesTask
                let attendance = try await attendanceTask
                let matchdays = try await matchdaysTask
                let trainings = try await trainingsTask

                let scopedTrainings = Self.filterByScope(
                    trainings,
                    teamID: \.teamId,
                    selectedTeamID: normalizedScopedTeamID
                )
                let scopedMatchdays = Self.filterByScope(
                    matchdays,
                    teamID: \.teamId,
                    selectedTeamID: normalizedScopedTeamID
                )
                let scopedMatches = Self.filterMatches(
                    matches,
                    matchdays: scopedMatchdays,
                    selectedTeamID: normalizedScopedTeamID
                )
                let scopedAttendance = Self.filterAttendance(
                    attendance,
                    playerIDs: Set(players.map(\.id)),
                    trainings: scopedTrainings,
                    matchdays: scopedMatchdays,
                    matches: scopedMatches
                )

                applyStats(
                    matches: scopedMatches,
                    attendance: scopedAttendance,
                    matchdays: scopedMatchdays,
                    players: players
                )
            }

            errorMessage = nil
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    private func applyStats(
        matches: [MatchLite],
        attendance: [AttendanceRow],
        matchdays: [Matchday],
        players: [Player]
    ) {
        let playedMatches = matches.filter(Self.isPlayedMatch)
        playedMatchesCount = playedMatches.count

        var localWins = 0
        var localDraws = 0
        var localLosses = 0
        var localGoalsFor = 0
        var localGoalsAgainst = 0
        var scorerTally: [String: Int] = [:]
        var historicScorerNamesByID: [String: String] = [:]

        for match in playedMatches {
            let homeScore = match.teams.first(where: { $0.side == "home" })?.score ?? 0
            let awayScore = match.teams.first(where: { $0.side == "away" })?.score ?? 0
            localGoalsFor += homeScore
            localGoalsAgainst += awayScore

            if homeScore > awayScore {
                localWins += 1
            } else if homeScore == awayScore {
                localDraws += 1
            } else {
                localLosses += 1
            }

            for scorer in match.scorers where scorer.side == "home" {
                scorerTally[scorer.playerId, default: 0] += 1
                if let playerName = scorer.playerName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !playerName.isEmpty {
                    historicScorerNamesByID[scorer.playerId] = playerName
                }
            }
        }

        let nameByID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.name) })
        let sortedPlayers = players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        wins = localWins
        draws = localDraws
        losses = localLosses
        totalFor = localGoalsFor
        totalAgainst = localGoalsAgainst

        let sortedPlayedMatches = playedMatches.sorted {
            $0.createdAt < $1.createdAt
        }
        avgForPerMatch = cumulativeAverageSeries(matches: sortedPlayedMatches, side: "home")
        avgAgainstPerMatch = cumulativeAverageSeries(matches: sortedPlayedMatches, side: "away")

        let plateauInfoByID = Dictionary(uniqueKeysWithValues: matchdays.map { ($0.id, $0.lieu ?? "Plateau") })
        let groupedPlateaux = groupPlateauMatches(from: sortedPlayedMatches, plateauLabelByID: plateauInfoByID)
        avgForPerPlateau = cumulativePlateauAverageSeries(groups: groupedPlateaux, side: "home")
        avgAgainstPerPlateau = cumulativePlateauAverageSeries(groups: groupedPlateaux, side: "away")
        plateauBands = groupedPlateaux.enumerated().map { index, group in
            PlateauBand(
                index: index + 1,
                label: group.label,
                color: Self.plateauPalette[index % Self.plateauPalette.count]
            )
        }

        scorers = scorerTally
            .map { playerID, goals in
                RankedStat(
                    id: playerID,
                    name: historicScorerNamesByID[playerID] ?? nameByID[playerID] ?? "Joueur inconnu",
                    value: goals
                )
            }
            .sorted {
                if $0.value == $1.value {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.value > $1.value
            }

        let trainingCountByPlayer = Dictionary(grouping: attendance.filter { $0.present && $0.sessionType.uppercased() == "TRAINING" }, by: \.playerId)
            .mapValues(\.count)
        let plateauCountByPlayer = Dictionary(grouping: attendance.filter { $0.present && ["PLATEAU", "MATCHDAY", "MATCH"].contains($0.sessionType.uppercased()) }, by: \.playerId)
            .mapValues(\.count)

        trainingPresence = sortedPlayers.map { player in
            RankedStat(
                id: player.id,
                name: player.name,
                value: trainingCountByPlayer[player.id] ?? 0
            )
        }
        .sorted {
            if $0.value == $1.value {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.value > $1.value
        }

        plateauPresence = sortedPlayers.map { player in
            RankedStat(
                id: player.id,
                name: player.name,
                value: plateauCountByPlayer[player.id] ?? 0
            )
        }
        .sorted {
            if $0.value == $1.value {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.value > $1.value
        }
    }

    private static func mergedSeasons(_ seasons: [Season], currentSeason: Season?) -> [Season] {
        var merged: [Season] = []
        for season in seasons where !merged.contains(where: { Self.seasonsEquivalent($0, season) }) {
            merged.append(season)
        }
        if let currentSeason {
            merged.removeAll { Self.seasonsEquivalent($0, currentSeason) }
            merged.insert(currentSeason, at: 0)
        }
        return merged.sorted { lhs, rhs in
            lhs.startDate > rhs.startDate
        }
    }

    private static func filterByScope<Item>(
        _ items: [Item],
        teamID: KeyPath<Item, String?>,
        selectedTeamID: String?
    ) -> [Item] {
        guard let selectedTeamID else { return items }
        return items.filter { item in
            guard let currentTeamID = item[keyPath: teamID]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !currentTeamID.isEmpty else {
                return true
            }
            return currentTeamID == selectedTeamID
        }
    }

    private static func filterMatches(
        _ matches: [MatchLite],
        matchdays: [Matchday],
        selectedTeamID: String?
    ) -> [MatchLite] {
        guard selectedTeamID != nil else { return matches }
        let allowedMatchdayIDs = Set(matchdays.map(\.id))
        return matches.filter { match in
            guard let matchdayID = match.matchdayId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !matchdayID.isEmpty else {
                return true
            }
            return allowedMatchdayIDs.contains(matchdayID)
        }
    }

    private static func filterAttendance(
        _ attendance: [AttendanceRow],
        playerIDs: Set<String>,
        trainings: [Training],
        matchdays: [Matchday],
        matches: [MatchLite]
    ) -> [AttendanceRow] {
        let trainingIDs = Set(trainings.map(\.id))
        let matchdayIDs = Set(matchdays.map(\.id))
        let matchIDs = Set(matches.map(\.id))

        return attendance.filter { row in
            guard playerIDs.contains(row.playerId) else { return false }

            switch row.sessionType.uppercased() {
            case "TRAINING":
                return trainingIDs.contains(row.sessionId)
            case "PLATEAU", "MATCHDAY":
                return matchdayIDs.contains(row.sessionId)
            case "MATCH":
                return matchIDs.contains(row.sessionId)
            default:
                return true
            }
        }
    }

    private func normalizedTeamID(_ teamID: String?) -> String? {
        guard let teamID = teamID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !teamID.isEmpty else {
            return nil
        }
        return teamID
    }

    private static func fallbackSeasons(
        club: Club,
        matches: [MatchLite],
        matchdays: [Matchday],
        trainings: [Training]
    ) -> [Season] {
        var seasonsByLabel: [String: Season] = [:]

        func registerSeason(_ season: Season) {
            if let existing = seasonsByLabel[season.label],
               !existing.id.hasPrefix("synthetic:") {
                return
            }
            seasonsByLabel[season.label] = season
        }

        func registerDate(_ date: Date) {
            let window = SeasonSupport.displayWindow(for: date, config: club.seasonConfig)
            guard seasonsByLabel[window.label] == nil else { return }
            registerSeason(Season(
                id: "synthetic:\(window.label)",
                clubId: club.id,
                key: window.label,
                label: window.label,
                startDate: DateFormatters.isoDateOnlyString(from: window.startDate),
                endDate: DateFormatters.isoDateOnlyString(from: window.endDate),
                isCurrent: nil
            ))
        }

        if let currentSeason = club.currentSeason {
            registerSeason(currentSeason)
        }
        matches.compactMap(\.season).forEach(registerSeason)
        matchdays.compactMap(\.season).forEach(registerSeason)
        trainings.compactMap(\.season).forEach(registerSeason)

        registerDate(Date())
        matches.compactMap { DateFormatters.parseISODate($0.date ?? $0.createdAt) }.forEach(registerDate)
        matchdays.compactMap { DateFormatters.parseISODate($0.date) }.forEach(registerDate)
        trainings.compactMap { DateFormatters.parseISODate($0.date) }.forEach(registerDate)

        return mergedSeasons(Array(seasonsByLabel.values), currentSeason: club.currentSeason)
    }

    private static func filterMatches(
        _ matches: [MatchLite],
        for season: Season?,
        config: ClubSeasonConfig?
    ) -> [MatchLite] {
        guard let season else { return matches }
        return matches.filter { match in
            if let embeddedSeason = match.season {
                return seasonsEquivalent(embeddedSeason, season)
            }
            guard let date = DateFormatters.parseISODate(match.date ?? match.createdAt) else { return false }
            return isDate(date, inside: season, config: config)
        }
    }

    private static func filterMatchdays(
        _ matchdays: [Matchday],
        for season: Season?,
        config: ClubSeasonConfig?
    ) -> [Matchday] {
        guard let season else { return matchdays }
        return matchdays.filter { matchday in
            if let embeddedSeason = matchday.season {
                return seasonsEquivalent(embeddedSeason, season)
            }
            guard let date = DateFormatters.parseISODate(matchday.date) else { return false }
            return isDate(date, inside: season, config: config)
        }
    }

    private static func filterTrainings(
        _ trainings: [Training],
        for season: Season?,
        config: ClubSeasonConfig?
    ) -> [Training] {
        guard let season else { return trainings }
        return trainings.filter { training in
            if let embeddedSeason = training.season {
                return seasonsEquivalent(embeddedSeason, season)
            }
            guard let date = DateFormatters.parseISODate(training.date) else { return false }
            return isDate(date, inside: season, config: config)
        }
    }

    private static func filterAttendance(
        _ attendance: [AttendanceRow],
        trainings: [Training],
        matchdays: [Matchday]
    ) -> [AttendanceRow] {
        let trainingIDs = Set(trainings.map(\.id))
        let matchdayIDs = Set(matchdays.map(\.id))

        return attendance.filter { row in
            switch row.sessionType.uppercased() {
            case "TRAINING":
                return trainingIDs.contains(row.sessionId)
            case "PLATEAU", "MATCHDAY", "MATCH":
                return matchdayIDs.contains(row.sessionId)
            default:
                return false
            }
        }
    }

    private static func seasonsEquivalent(_ lhs: Season, _ rhs: Season) -> Bool {
        lhs.id == rhs.id
            || lhs.label == rhs.label
            || (lhs.startDate == rhs.startDate && lhs.endDate == rhs.endDate)
    }

    private static func isDate(_ date: Date, inside season: Season, config: ClubSeasonConfig?) -> Bool {
        if let startDate = DateFormatters.parseISODate(season.startDate),
           let endDate = DateFormatters.parseISODate(season.endDate) {
            return date >= startDate && date <= endDate
        }
        return SeasonSupport.displayWindow(for: date, config: config).label == season.label
    }

    private static let plateauPalette: [Color] = [
        Color(red: 0.99, green: 0.95, blue: 0.78),
        Color(red: 0.88, green: 0.95, blue: 0.99),
        Color(red: 0.91, green: 0.84, blue: 1.0),
        Color(red: 0.86, green: 0.99, blue: 0.9),
        Color(red: 1.0, green: 0.89, blue: 0.9)
    ]

    private static func isPlayedMatch(_ match: MatchLite) -> Bool {
        let rawStatus = match.status?.uppercased()
        if rawStatus == "CANCELLED" || rawStatus == "CANCELED" || rawStatus == "ANNULE" {
            return false
        }
        if let played = match.played {
            return played
        }
        let homeScore = match.teams.first(where: { $0.side == "home" })?.score ?? 0
        let awayScore = match.teams.first(where: { $0.side == "away" })?.score ?? 0
        return homeScore != 0 || awayScore != 0 || !match.scorers.isEmpty
    }

    private func cumulativeAverageSeries(matches: [MatchLite], side: String) -> [SeriesPoint] {
        var sum = 0.0
        var result: [SeriesPoint] = []

        for (index, match) in matches.enumerated() {
            let score = Double(match.teams.first(where: { $0.side == side })?.score ?? 0)
            sum += score
            let currentIndex = Double(index + 1)
            result.append(SeriesPoint(x: currentIndex, y: sum / currentIndex))
        }

        return result
    }

    private func cumulativePlateauAverageSeries(groups: [(label: String, matches: [MatchLite])], side: String) -> [SeriesPoint] {
        var cumulative = 0.0
        var result: [SeriesPoint] = []

        for (index, group) in groups.enumerated() {
            guard !group.matches.isEmpty else { continue }
            let average = group.matches
                .map { Double($0.teams.first(where: { $0.side == side })?.score ?? 0) }
                .reduce(0, +) / Double(group.matches.count)
            cumulative += average
            let currentIndex = Double(index + 1)
            result.append(SeriesPoint(x: currentIndex, y: cumulative / currentIndex))
        }

        return result
    }

    private func groupPlateauMatches(from matches: [MatchLite], plateauLabelByID: [String: String]) -> [(label: String, matches: [MatchLite])] {
        var groupsByID: [String: (createdAt: String, label: String, matches: [MatchLite])] = [:]

        for match in matches where match.type == "PLATEAU" {
            let key = match.matchdayId ?? "__plateau__\(match.id)"
            let label = match.matchdayId.flatMap { plateauLabelByID[$0] } ?? "Plateau"

            if groupsByID[key] == nil {
                groupsByID[key] = (createdAt: match.createdAt, label: label, matches: [match])
            } else {
                groupsByID[key]?.matches.append(match)
                if match.createdAt < (groupsByID[key]?.createdAt ?? match.createdAt) {
                    groupsByID[key]?.createdAt = match.createdAt
                }
            }
        }

        return groupsByID.values
            .sorted { $0.createdAt < $1.createdAt }
            .map { ($0.label, $0.matches.sorted { $0.createdAt < $1.createdAt }) }
    }
}

private enum TeamTab: String, CaseIterable, Identifiable {
    case players = "Effectif"
    case tactic = "Tactique"
    case stats = "Stats"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .players:
            return "person.3"
        case .tactic:
            return "sportscourt"
        case .stats:
            return "chart.bar"
        }
    }
}

struct PlayersHomeView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var teamScopeStore: TeamScopeStore
    @StateObject private var viewModel = PlayersHomeViewModel()
    @StateObject private var statsViewModel = TeamStatsViewModel()
    @State private var query = ""
    @State private var isCreateSheetPresented = false
    @State private var selectedTab: TeamTab = .players
    private var dataCacheKey: String {
        "players-home-\(authStore.me?.id ?? "anonymous")-\(teamScopeStore.selectedTeamID ?? "all")"
    }

    private var taskReloadKey: String {
        "\(dataCacheKey)-\(teamScopeStore.scopeRevision)"
    }

    private var tacticScopeKey: String? {
        normalizedTeamID(teamScopeStore.selectedTeamID)
    }

    private var tacticRequiresActiveTeamSelection: Bool {
        guard let role = authStore.me?.role else { return false }
        return (role == .direction || role == .coach) && !teamScopeStore.teams.isEmpty && tacticScopeKey == nil
    }

    private var selectedTeamFormat: String? {
        guard let selectedTeamID = teamScopeStore.selectedTeamID else { return nil }
        return teamScopeStore.teams.first(where: { $0.id == selectedTeamID })?.format
    }

    private var tacticPlayersOnField: Int {
        switch selectedTeamFormat?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "3v3":
            return 3
        case "8v8":
            return 8
        case "11v11":
            return 11
        default:
            return 5
        }
    }

    private var searchedPlayers: [Player] {
        guard !query.isEmpty else { return viewModel.players }
        return viewModel.players.filter { player in
            let haystack = [
                player.name,
                player.firstName,
                player.lastName,
                player.email,
                player.primaryPosition,
                player.secondaryPosition
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return haystack.contains(query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current))
        }
    }

    private var activePlayers: [Player] {
        searchedPlayers.filter(\.isActive)
    }

    private var inactivePlayers: [Player] {
        searchedPlayers.filter { !$0.isActive }
    }

    private func playerDisplayName(_ player: Player) -> String {
        let firstName = player.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lastName = player.lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fullName = [firstName, lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullName.isEmpty {
            return fullName
        }
        let legacyName = player.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return legacyName.isEmpty ? "Joueur" : legacyName
    }

    var body: some View {
        NavigationStack {
            Group {
                switch selectedTab {
                case .players:
                    playersList
                case .tactic:
                    tacticList
                case .stats:
                    statsList
                }
            }
            .navigationTitle("Mon équipe")
            .navigationBarTitleDisplayMode(.large)
            .appChrome()
            .overlay(alignment: .bottomTrailing) {
                if selectedTab == .players {
                    Button {
                        isCreateSheetPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.accentColor, in: Circle())
                            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                    .accessibilityLabel("Ajouter un joueur")
                }
            }
            .task(id: taskReloadKey) {
                await viewModel.load(cacheKey: dataCacheKey, teamID: teamScopeStore.selectedTeamID)
                if selectedTab == .stats {
                    await statsViewModel.load(
                        players: viewModel.players,
                        teamID: teamScopeStore.selectedTeamID,
                        refreshSeasonCatalog: true
                    )
                }
            }
            .sheet(isPresented: $isCreateSheetPresented) {
                CreatePlayerSheet { payload in
                    await viewModel.create(
                        firstName: payload.firstName,
                        lastName: payload.lastName,
                        primaryPosition: payload.primaryPosition,
                        secondaryPosition: payload.secondaryPosition,
                        cacheKey: dataCacheKey
                    )
                    isCreateSheetPresented = false
                }
                .presentationDetents([.large])
            }
            .alert("Erreur", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { _ in viewModel.errorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("Erreur", isPresented: Binding(
                get: { statsViewModel.errorMessage != nil },
                set: { _ in statsViewModel.errorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statsViewModel.errorMessage ?? "")
            }
            .onChange(of: selectedTab) { newValue in
                guard newValue == .stats else { return }
                Task {
                    await statsViewModel.load(
                        players: viewModel.players,
                        teamID: teamScopeStore.selectedTeamID,
                        refreshSeasonCatalog: true
                    )
                }
            }
            .onChange(of: statsViewModel.selectedSeasonID) { _ in
                guard selectedTab == .stats else { return }
                Task {
                    await statsViewModel.load(players: viewModel.players, teamID: teamScopeStore.selectedTeamID)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .playerDidUpdate)) { _ in
                Task {
                    await viewModel.load(cacheKey: dataCacheKey, teamID: teamScopeStore.selectedTeamID, forceRefresh: true)
                    if selectedTab == .stats {
                        await statsViewModel.load(
                            players: viewModel.players,
                            teamID: teamScopeStore.selectedTeamID,
                            refreshSeasonCatalog: true
                        )
                    }
                }
            }
        }
    }

    private var playersList: some View {
        List {
            Section {
                Picker("Vue", selection: $selectedTab) {
                    ForEach(TeamTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Rechercher un joueur", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            playersSection
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.load(cacheKey: dataCacheKey, teamID: teamScopeStore.selectedTeamID, forceRefresh: true)
            if selectedTab == .stats {
                await statsViewModel.load(players: viewModel.players, teamID: teamScopeStore.selectedTeamID)
            }
        }
    }

    private var tacticList: some View {
        List {
            Section {
                Picker("Vue", selection: $selectedTab) {
                    ForEach(TeamTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            tacticSection
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.load(cacheKey: dataCacheKey, teamID: teamScopeStore.selectedTeamID, forceRefresh: true)
            if selectedTab == .stats {
                await statsViewModel.load(players: viewModel.players, teamID: teamScopeStore.selectedTeamID)
            }
        }
    }

    private var statsList: some View {
        List {
            Section {
                Picker("Vue", selection: $selectedTab) {
                    ForEach(TeamTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            statsSection
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.load(cacheKey: dataCacheKey, teamID: teamScopeStore.selectedTeamID, forceRefresh: true)
            if selectedTab == .stats {
                await statsViewModel.load(players: viewModel.players, teamID: teamScopeStore.selectedTeamID)
            }
        }
    }

    private var playersSection: some View {
        Group {
            if activePlayers.isEmpty && inactivePlayers.isEmpty {
                Section("Effectif") {
                    Text(query.isEmpty ? "Aucun joueur" : "Aucun joueur pour cette recherche")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Effectif") {
                    if activePlayers.isEmpty {
                        Text(query.isEmpty ? "Aucun joueur dans l'effectif" : "Aucun joueur actif pour cette recherche")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(activePlayers) { player in
                        NavigationLink {
                            PlayerDetailView(playerID: player.id)
                        } label: {
                            Text(playerDisplayName(player))
                                .font(.headline)
                        }
                    }

                    if query.isEmpty && viewModel.canLoadMorePlayers {
                        Button {
                            Task { await viewModel.loadMore(cacheKey: dataCacheKey, teamID: teamScopeStore.selectedTeamID) }
                        } label: {
                            HStack {
                                Spacer()
                                Text(viewModel.isLoadingMore ? "Chargement..." : "Charger plus")
                                Spacer()
                            }
                        }
                        .disabled(viewModel.isLoadingMore)
                    }
                }

                if !inactivePlayers.isEmpty {
                    Section("Hors effectif") {
                        ForEach(inactivePlayers) { player in
                            NavigationLink {
                                PlayerDetailView(playerID: player.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playerDisplayName(player))
                                        .font(.headline)
                                    Text(player.teamName ?? player.teamId ?? "Équipe non renseignée")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var tacticSection: some View {
        Section("Tactique") {
            if let tacticScopeKey {
                TeamTacticCard(scopeKey: tacticScopeKey, playersOnField: tacticPlayersOnField)
                    .id("team-tactic-\(tacticScopeKey)-\(tacticPlayersOnField)")
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            } else if tacticRequiresActiveTeamSelection {
                Text("Selectionnez une equipe active pour acceder a la tactique de cette equipe.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Aucune equipe active disponible.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statsSection: some View {
        TeamStatsSummaryView(viewModel: statsViewModel)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
    }

    private func normalizedTeamID(_ teamID: String?) -> String? {
        guard let teamID = teamID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !teamID.isEmpty else {
            return nil
        }
        return teamID
    }
}

private struct TacticSlot: Codable, Identifiable, Equatable {
    let id: String
    var label: String
    var pointID: String
}

private struct SavedTactic: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let slots: [TacticSlot]
}

private struct TeamTacticCard: View {
    private struct FormationTemplate: Identifiable {
        let key: String
        let label: String
        let lines: [Int]

        var id: String { key }
    }

    private enum SaveMode: String, CaseIterable, Identifiable {
        case overwrite = "Écraser l'actuelle"
        case createNew = "Créer une nouvelle"

        var id: String { rawValue }
    }

    let scopeKey: String
    let playersOnField: Int
    @State private var tactics: [SavedTactic] = []
    @State private var selectedTacticID = ""
    @State private var workingSlots: [TacticSlot] = []
    @State private var dragOffsets: [String: CGSize] = [:]
    @State private var activeDragSlotID: String?
    @State private var isSaveSheetPresented = false
    @State private var newTacticName = ""
    @State private var saveMode: SaveMode = .overwrite

    private let points = TacticalFieldLayout.snapPoints

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Menu {
                    ForEach(tactics) { tactic in
                        Button {
                            apply(tactic: tactic)
                        } label: {
                            HStack {
                                Text(tactic.name)
                                if tactic.id == selectedTacticID {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text((selectedTactic?.name ?? "Tactique") + (hasUnsavedChanges ? " *" : ""))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            TacticalPitchView(centerCircleScale: 0.22) { fieldSize in
                let nodeSize = editorNodeSize(for: fieldSize.width)
                ZStack {
                    if activeDragSlotID != nil {
                        ForEach(points) { point in
                            Circle()
                                .fill(.white.opacity(0.28))
                                .frame(width: 10, height: 10)
                                .position(x: fieldSize.width * point.normalizedX, y: fieldSize.height * point.normalizedY)
                        }
                    }

                    ForEach(Array(workingSlots.enumerated()), id: \.element.id) { _, slot in
                        if let point = point(by: slot.pointID) {
                            TeamTacticPositionNode(label: positionLabel(for: point), color: uniformNodeColor, size: nodeSize)
                                .position(
                                    x: fieldSize.width * point.normalizedX + (dragOffsets[slot.id]?.width ?? 0),
                                    y: fieldSize.height * point.normalizedY + (dragOffsets[slot.id]?.height ?? 0)
                                )
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            activeDragSlotID = slot.id
                                            dragOffsets[slot.id] = value.translation
                                        }
                                        .onEnded { value in
                                            handleDrop(
                                                slotID: slot.id,
                                                startPointID: slot.pointID,
                                                translation: value.translation,
                                                fieldSize: fieldSize
                                            )
                                        }
                                )
                        }
                    }
                }
            }

            if hasUnsavedChanges {
                HStack(spacing: 10) {
                    Button("Sauvegarder") {
                        saveMode = selectedTactic == nil ? .createNew : .overwrite
                        newTacticName = suggestedSaveName
                        isSaveSheetPresented = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Réinitialiser") {
                        resetCurrentChanges()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onAppear {
            loadTactics()
        }
        .onChange(of: scopeKey) { _ in
            loadTactics()
        }
        .onChange(of: playersOnField) { _ in
            loadTactics()
        }
        .sheet(isPresented: $isSaveSheetPresented) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Mode", selection: $saveMode) {
                        ForEach(SaveMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if saveMode == .overwrite {
                        Text("Tactique actuelle: \(selectedTactic?.name ?? "Aucune")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("Nom de la tactique", text: $newTacticName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .navigationTitle("Sauvegarder")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") {
                            isSaveSheetPresented = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Enregistrer") {
                            saveFromSheet()
                            isSaveSheetPresented = false
                        }
                        .disabled(saveMode == .createNew && newTacticName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.height(250)])
        }
    }

    private var selectedTactic: SavedTactic? {
        tactics.first(where: { $0.id == selectedTacticID })
    }

    private var hasUnsavedChanges: Bool {
        guard let tactic = selectedTactic else { return false }
        return normalized(workingSlots) != normalized(tactic.slots)
    }

    private var suggestedSaveName: String {
        guard let current = selectedTactic else { return "Nouvelle tactique" }
        return "\(current.name) (copie)"
    }

    private func loadTactics() {
        let currentSelectedID = UserDefaults.standard.string(forKey: selectedTacticStorageKey)
        let legacySelectedID = UserDefaults.standard.string(forKey: legacySelectedTacticStorageKey)
        selectedTacticID = currentSelectedID ?? legacySelectedID ?? ""

        let currentDecoded = decodedTactics(from: tacticsJSON)
        let legacyDecoded = decodedTactics(from: legacyTacticsJSON)
        let usingLegacyStorage = currentDecoded.isEmpty && !legacyDecoded.isEmpty
        let storedTactics = currentDecoded.isEmpty ? legacyDecoded : currentDecoded
        let sanitizedStoredTactics = storedTactics.map(sanitizedTactic)
        let didMigrateStoredTactics = sanitizedStoredTactics != storedTactics

        if !sanitizedStoredTactics.isEmpty {
            tactics = sanitizedStoredTactics
            if usingLegacyStorage || didMigrateStoredTactics {
                persistTactics()
                persistSelectedTacticID()
            }
        } else {
            tactics = defaultTactics
            persistTactics()
        }

        if !tactics.contains(where: { $0.id == selectedTacticID }) {
            selectedTacticID = tactics.first?.id ?? ""
            persistSelectedTacticID()
        }
        workingSlots = preparedSlots(selectedTactic?.slots ?? tactics.first?.slots ?? [])
        dragOffsets = [:]
        activeDragSlotID = nil
    }

    private func decodedTactics(from json: String) -> [SavedTactic] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SavedTactic].self, from: data) else {
            return []
        }
        return decoded.filter { $0.slots.count == normalizedPlayersOnField }
    }

    private func apply(tactic: SavedTactic) {
        selectedTacticID = tactic.id
        workingSlots = preparedSlots(tactic.slots)
        dragOffsets = [:]
        persistSelectedTacticID()
    }

    private func saveAsNewTactic() {
        let name = newTacticName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let prepared = preparedSlots(workingSlots)
        let new = SavedTactic(id: UUID().uuidString, name: name, slots: prepared)
        tactics.append(new)
        selectedTacticID = new.id
        workingSlots = new.slots
        persistTactics()
        persistSelectedTacticID()
    }

    private func overwriteCurrentTactic() {
        guard let selected = selectedTactic,
              let index = tactics.firstIndex(where: { $0.id == selected.id }) else {
            saveAsNewTactic()
            return
        }

        let prepared = preparedSlots(workingSlots)
        tactics[index] = SavedTactic(id: selected.id, name: selected.name, slots: prepared)
        workingSlots = prepared
        persistTactics()
    }

    private func saveFromSheet() {
        switch saveMode {
        case .overwrite:
            overwriteCurrentTactic()
        case .createNew:
            saveAsNewTactic()
        }
    }

    private func persistTactics() {
        guard let data = try? JSONEncoder().encode(tactics),
              let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(json, forKey: tacticsStorageKey)
    }

    private func persistSelectedTacticID() {
        UserDefaults.standard.set(selectedTacticID, forKey: selectedTacticStorageKey)
    }

    private var tacticsJSON: String {
        UserDefaults.standard.string(forKey: tacticsStorageKey) ?? ""
    }

    private var legacyTacticsJSON: String {
        UserDefaults.standard.string(forKey: legacyTacticsStorageKey) ?? ""
    }

    private var tacticsStorageKey: String {
        "izifoot.team.tactics.json.\(scopeKey).\(normalizedPlayersOnField)"
    }

    private var selectedTacticStorageKey: String {
        "izifoot.team.tactics.selected.\(scopeKey).\(normalizedPlayersOnField)"
    }

    private var legacyTacticsStorageKey: String {
        "izifoot.team.tactics.json.\(scopeKey)"
    }

    private var legacySelectedTacticStorageKey: String {
        "izifoot.team.tactics.selected.\(scopeKey)"
    }

    private func handleDrop(slotID: String, startPointID: String, translation: CGSize, fieldSize: CGSize) {
        defer {
            dragOffsets[slotID] = .zero
            activeDragSlotID = nil
        }
        let start = point(by: startPointID) ?? points[0]
        let destinationX = start.normalizedX + (translation.width / max(fieldSize.width, 1))
        let destinationY = start.normalizedY + (translation.height / max(fieldSize.height, 1))

        guard let nearest = nearestPoint(toX: destinationX, y: destinationY) else { return }

        guard let sourceIndex = workingSlots.firstIndex(where: { $0.id == slotID }) else { return }
        if let occupiedIndex = workingSlots.firstIndex(where: { $0.pointID == nearest.id && $0.id != slotID }) {
            let previous = workingSlots[sourceIndex].pointID
            workingSlots[sourceIndex].pointID = nearest.id
            workingSlots[occupiedIndex].pointID = previous
            if let updatedPoint = point(by: nearest.id) {
                workingSlots[sourceIndex].label = positionLabel(for: updatedPoint)
            }
            if let swappedPoint = point(by: previous) {
                workingSlots[occupiedIndex].label = positionLabel(for: swappedPoint)
            }
        } else {
            workingSlots[sourceIndex].pointID = nearest.id
            workingSlots[sourceIndex].label = positionLabel(for: nearest)
        }
    }

    private func nearestPoint(toX x: CGFloat, y: CGFloat) -> TacticalGridPoint? {
        points.min { lhs, rhs in
            let dl = hypot(lhs.normalizedX - x, lhs.normalizedY - y)
            let dr = hypot(rhs.normalizedX - x, rhs.normalizedY - y)
            return dl < dr
        }
    }

    private func point(by id: String) -> TacticalGridPoint? {
        TacticalFieldLayout.point(by: id)
    }

    private func normalized(_ slots: [TacticSlot]) -> [TacticSlot] {
        slots.sorted { $0.id < $1.id }
    }

    private func preparedSlots(_ slots: [TacticSlot]) -> [TacticSlot] {
        let migratedPointIDs = TacticalFieldLayout.migratePointIDs(slots.map(\.pointID))
        return normalized(zip(slots, migratedPointIDs).map { slot, pointID in
            var copy = slot
            copy.pointID = pointID
            if let point = point(by: pointID) {
                copy.label = positionLabel(for: point)
            }
            return copy
        })
    }

    private func sanitizedTactic(_ tactic: SavedTactic) -> SavedTactic {
        SavedTactic(id: tactic.id, name: tactic.name, slots: preparedSlots(tactic.slots))
    }

    private func resetCurrentChanges() {
        guard let selectedTactic else { return }
        workingSlots = preparedSlots(selectedTactic.slots)
        dragOffsets = [:]
        activeDragSlotID = nil
    }

    private var normalizedPlayersOnField: Int {
        switch playersOnField {
        case 3, 5, 8, 11:
            return playersOnField
        default:
            return max(1, playersOnField)
        }
    }

    private var formationTemplates: [FormationTemplate] {
        switch normalizedPlayersOnField {
        case 3:
            return [
                FormationTemplate(key: "def", label: "1-0-1", lines: [1, 0, 1]),
                FormationTemplate(key: "mid", label: "1-1-0", lines: [1, 1, 0]),
                FormationTemplate(key: "att", label: "0-1-1", lines: [0, 1, 1]),
            ]
        case 5:
            return [
                FormationTemplate(key: "balanced", label: "2-1-1", lines: [2, 1, 1]),
                FormationTemplate(key: "middle", label: "1-2-1", lines: [1, 2, 1]),
                FormationTemplate(key: "attack", label: "1-1-2", lines: [1, 1, 2]),
            ]
        case 8:
            return [
                FormationTemplate(key: "balanced", label: "3-2-2", lines: [3, 2, 2]),
                FormationTemplate(key: "middle", label: "2-3-2", lines: [2, 3, 2]),
                FormationTemplate(key: "attack", label: "2-2-3", lines: [2, 2, 3]),
            ]
        case 11:
            return [
                FormationTemplate(key: "balanced", label: "4-3-3", lines: [4, 3, 3]),
                FormationTemplate(key: "middle", label: "4-4-2", lines: [4, 4, 2]),
                FormationTemplate(key: "attack", label: "3-5-2", lines: [3, 5, 2]),
            ]
        default:
            return [
                FormationTemplate(
                    key: "balanced",
                    label: "Équilibre",
                    lines: [max(1, normalizedPlayersOnField - 2), 1, 0]
                ),
            ]
        }
    }

    private var defaultTactics: [SavedTactic] {
        formationTemplates.map { template in
            SavedTactic(
                id: "default-\(normalizedPlayersOnField)-\(template.key)",
                name: template.label,
                slots: buildDefaultSlots(lines: template.lines)
            )
        }
    }

    private func buildDefaultSlots(lines: [Int]) -> [TacticSlot] {
        TacticalFieldLayout.formationPoints(playersOnField: normalizedPlayersOnField, lines: lines)
            .enumerated()
            .map { index, point in
            TacticSlot(
                id: "s\(index + 1)",
                label: positionLabel(for: point),
                pointID: point.id
            )
        }
    }

    private func editorNodeSize(for fieldWidth: CGFloat) -> CGFloat {
        let baseDivisor: CGFloat = normalizedPlayersOnField >= 11 ? 8.4 : normalizedPlayersOnField >= 8 ? 7.8 : 7.0
        return min(max(fieldWidth / baseDivisor, 42), 50)
    }

    private var uniformNodeColor: Color {
        Color(red: 0.14, green: 0.43, blue: 0.89)
    }

    private func positionLabel(for point: TacticalGridPoint) -> String {
        if point.y >= 82 { return "GK" }

        if point.y >= 58 {
            if point.x < 33 { return "DG" }
            if point.x > 67 { return "DD" }
            return "DC"
        }

        if point.y >= 42 {
            if point.x < 33 { return "MG" }
            if point.x > 67 { return "MD" }
            return "MC"
        }

        if point.x < 33 { return "AG" }
        if point.x > 67 { return "AD" }
        return "BU"
    }
}

private struct TeamTacticPositionNode: View {
    let label: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.82), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
}

private enum TeamStatsRankTab: String, CaseIterable, Identifiable {
    case scorers = "Buteurs"
    case trainings = "Présences (Entraînements)"
    case plateaux = "Présences (Plateaux)"

    var id: String { rawValue }
}

private enum TeamStatsChartMode: String, CaseIterable, Identifiable {
    case match = "Par match"
    case plateau = "Par plateau"

    var id: String { rawValue }
}

private struct TeamStatsSummaryView: View {
    @ObservedObject var viewModel: TeamStatsViewModel
    @State private var selectedRankTab: TeamStatsRankTab = .scorers
    @State private var selectedChartMode: TeamStatsChartMode = .match

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !viewModel.seasons.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saison")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Menu {
                        ForEach(viewModel.seasons) { season in
                            Button {
                                viewModel.selectedSeasonID = season.id
                            } label: {
                                Text(season.label)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(viewModel.seasonLabel.isEmpty ? "Choisir une saison" : viewModel.seasonLabel)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }

            if viewModel.playedMatchesCount == 0 {
                VStack(spacing: 12) {
                    Image(systemName: "soccerball")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Aucun match n'a été joué pour le moment")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                TeamStatCard(
                    title: "Matchs joués",
                    value: "\(viewModel.playedMatchesCount)",
                    systemImage: "flag.checkered"
                )

                HStack(spacing: 12) {
                    TeamStatCard(title: "Buts marqués", value: "\(viewModel.totalFor)", systemImage: "soccerball")
                    TeamStatCard(title: "Buts encaissés", value: "\(viewModel.totalAgainst)", systemImage: "shield.lefthalf.filled")
                }

                HStack(spacing: 12) {
                    TeamStatCard(title: "Victoires", value: "\(viewModel.wins)", systemImage: "checkmark.seal.fill")
                    TeamStatCard(title: "Nuls", value: "\(viewModel.draws)", systemImage: "equal.circle.fill")
                    TeamStatCard(title: "Défaites", value: "\(viewModel.losses)", systemImage: "xmark.seal.fill")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Picker("Vue", selection: $selectedChartMode) {
                        ForEach(TeamStatsChartMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    TeamStatsLineChartCard(
                        title: "Buts moyens marqués",
                        series: selectedChartMode == .match ? viewModel.avgForPerMatch : viewModel.avgForPerPlateau,
                        bands: selectedChartMode == .plateau ? viewModel.plateauBands : []
                    )

                    TeamStatsLineChartCard(
                        title: "Buts moyens encaissés",
                        series: selectedChartMode == .match ? viewModel.avgAgainstPerMatch : viewModel.avgAgainstPerPlateau,
                        bands: selectedChartMode == .plateau ? viewModel.plateauBands : []
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Picker("Classement", selection: $selectedRankTab) {
                        ForEach(TeamStatsRankTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(sectionTitle)
                        .font(.headline)

                    if currentRows.isEmpty {
                        Text(emptyStateTitle)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(currentRows.enumerated()), id: \.element.id) { index, row in
                            HStack {
                                Text("\(index + 1)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .leading)
                                Text(row.name)
                                Spacer()
                                Text("\(row.value)")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var currentRows: [TeamStatsViewModel.RankedStat] {
        switch selectedRankTab {
        case .scorers:
            return viewModel.scorers
        case .trainings:
            return viewModel.trainingPresence
        case .plateaux:
            return viewModel.plateauPresence
        }
    }

    private var sectionTitle: String {
        switch selectedRankTab {
        case .scorers:
            return "Classement des buteurs"
        case .trainings:
            return "Présences aux entraînements"
        case .plateaux:
            return "Présences aux plateaux"
        }
    }

    private var emptyStateTitle: String {
        switch selectedRankTab {
        case .scorers:
            return "Pas encore de buteurs enregistrés."
        case .trainings, .plateaux:
            return "Aucune présence enregistrée."
        }
    }
}

private struct TeamStatsLineChartCard: View {
    let title: String
    let series: [TeamStatsViewModel.SeriesPoint]
    let bands: [TeamStatsViewModel.PlateauBand]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if series.isEmpty {
                Text("Pas encore de données.")
                    .foregroundStyle(.secondary)
            } else {
                GeometryReader { proxy in
                    let size = proxy.size
                    let path = buildPath(in: size)
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))

                        if !bands.isEmpty {
                            ForEach(bands) { band in
                                Rectangle()
                                    .fill(band.color.opacity(0.32))
                                    .frame(width: bandWidth(in: size.width))
                                    .position(
                                        x: xPosition(for: Double(band.index), width: size.width),
                                        y: size.height / 2
                                    )
                            }
                        }

                        VStack {
                            HStack {
                                metricBadge(title: "min", value: minY)
                                Spacer()
                                metricBadge(title: "moy", value: avgY)
                                Spacer()
                                metricBadge(title: "max", value: maxY)
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                            Spacer()
                        }

                        Path { pathValue in
                            pathValue.addPath(path)
                        }
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                        ForEach(series) { point in
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 7, height: 7)
                                .position(
                                    x: xPosition(for: point.x, width: size.width),
                                    y: yPosition(for: point.y, height: size.height)
                                )
                        }
                    }
                }
                .frame(height: 220)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var minX: Double { series.map(\.x).min() ?? 0 }
    private var maxX: Double { series.map(\.x).max() ?? 1 }
    private var maxSeriesY: Double { max(series.map(\.y).max() ?? 1, 1) }
    private var minY: Double { series.map(\.y).min() ?? 0 }
    private var maxY: Double { series.map(\.y).max() ?? 0 }
    private var avgY: Double {
        guard !series.isEmpty else { return 0 }
        return series.map(\.y).reduce(0, +) / Double(series.count)
    }

    private func buildPath(in size: CGSize) -> Path {
        var path = Path()
        guard let first = series.first else { return path }

        path.move(to: CGPoint(
            x: xPosition(for: first.x, width: size.width),
            y: yPosition(for: first.y, height: size.height)
        ))

        for point in series.dropFirst() {
            path.addLine(to: CGPoint(
                x: xPosition(for: point.x, width: size.width),
                y: yPosition(for: point.y, height: size.height)
            ))
        }

        return path
    }

    private func xPosition(for value: Double, width: CGFloat) -> CGFloat {
        let pad: CGFloat = 28
        let span = max(maxX - minX, 1)
        return pad + CGFloat((value - minX) / span) * (width - pad * 2)
    }

    private func yPosition(for value: Double, height: CGFloat) -> CGFloat {
        let pad: CGFloat = 28
        let span = max(maxSeriesY, 1)
        return (height - pad) - CGFloat(value / span) * (height - pad * 2)
    }

    private func bandWidth(in width: CGFloat) -> CGFloat {
        guard series.count > 1 else { return max(width - 56, 40) }
        return (width - 56) / CGFloat(series.count)
    }

    private func metricBadge(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(prettyAvg(value))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func prettyAvg(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return String(format: "%.2f", rounded)
    }
}

private struct TeamStatCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct CreatePlayerPayload {
    let firstName: String
    let lastName: String?
    let primaryPosition: String?
    let secondaryPosition: String?
}

struct CreatePlayerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var primaryPosition = ""
    @State private var secondaryPosition = ""

    let onSubmit: (CreatePlayerPayload) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Ajout rapide") {
                    TextField("Prénom", text: $firstName)
                    TextField("Nom", text: $lastName)
                    TextField("Poste principal", text: $primaryPosition)
                    TextField("Poste secondaire", text: $secondaryPosition)
                }

                Section {
                    Text("Seul le prénom est requis. Vous pourrez compléter le nom et les coordonnées plus tard depuis la fiche joueur.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nouveau joueur")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        Task {
                            await onSubmit(
                                CreatePlayerPayload(
                                    firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                                    lastName: normalizedField(lastName),
                                    primaryPosition: normalizedField(primaryPosition),
                                    secondaryPosition: normalizedField(secondaryPosition)
                                )
                            )
                        }
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func normalizedField(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
