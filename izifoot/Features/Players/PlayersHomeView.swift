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

    private let api: IzifootAPI

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
        let email: String?
        let phone: String?
        let isChild: Bool
        let parentContacts: [CachedParentContact]
        let teamId: String?
    }

    private struct PlayersHomeCachePayload: Codable {
        let players: [CachedPlayer]
        let nextOffset: Int
        let canLoadMore: Bool
    }

    var canLoadMorePlayers: Bool {
        canLoadMore && !isLoading && !isLoadingMore
    }

    func load(cacheKey: String, forceRefresh: Bool = false) async {
        var hasCachedData = false
        if !forceRefresh,
           let cached = await PersistentDataCache.shared.read(PlayersHomeCachePayload.self, forKey: cacheKey) {
            players = cached.players.map { cached in
                Player(
                    id: cached.id,
                    name: cached.name,
                    firstName: cached.firstName,
                    lastName: cached.lastName,
                    primaryPosition: cached.primaryPosition,
                    secondaryPosition: cached.secondaryPosition,
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
                    teamId: cached.teamId
                )
            }
            nextOffset = cached.nextOffset
            canLoadMore = cached.canLoadMore
            hasCachedData = true
            errorMessage = nil
        }

        do {
            let response = try await api.players(limit: pageSize, offset: 0)
            players = response.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            nextOffset = response.pagination.offset + response.pagination.returned
            canLoadMore = response.pagination.returned >= response.pagination.limit && response.pagination.returned > 0
            await persistCache(forKey: cacheKey)
            errorMessage = nil
        } catch {
            if !error.isCancellationError, !hasCachedData { errorMessage = error.localizedDescription }
        }
    }

    func loadMore(cacheKey: String) async {
        guard canLoadMorePlayers else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await api.players(limit: pageSize, offset: nextOffset)
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

    func create(
        firstName: String,
        lastName: String,
        email: String,
        phone: String,
        primaryPosition: String,
        secondaryPosition: String?,
        cacheKey: String
    ) async {
        do {
            let created = try await api.createPlayer(
                firstName: firstName,
                lastName: lastName,
                email: email,
                phone: phone,
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
                        teamId: player.teamId
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
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI? = nil) {
        self.api = api ?? IzifootAPI()
    }

    func load(players: [Player]) async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let matchesTask = api.allMatches()
            async let attendanceTask = api.allAttendance()

            let matches = try await matchesTask
            let attendance = try await attendanceTask

            let playedMatches = matches.filter(Self.isPlayedMatch)
            playedMatchesCount = playedMatches.count

            var localWins = 0
            var localDraws = 0
            var localLosses = 0
            var localGoalsFor = 0
            var localGoalsAgainst = 0
            var scorerTally: [String: Int] = [:]

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

            let matchdays = try await api.allMatchdays()
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
                    RankedStat(id: playerID, name: nameByID[playerID] ?? playerID, value: goals)
                }
                .sorted {
                    if $0.value == $1.value {
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    return $0.value > $1.value
                }

            let trainingCountByPlayer = Dictionary(grouping: attendance.filter { $0.present && $0.sessionType == "TRAINING" }, by: \.playerId)
                .mapValues(\.count)
            let plateauCountByPlayer = Dictionary(grouping: attendance.filter { $0.present && $0.sessionType == "PLATEAU" }, by: \.playerId)
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

            errorMessage = nil
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
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
    @StateObject private var viewModel = PlayersHomeViewModel()
    @StateObject private var statsViewModel = TeamStatsViewModel()
    @State private var query = ""
    @State private var isCreateSheetPresented = false
    @State private var selectedTab: TeamTab = .players
    private var dataCacheKey: String { "players-home-\(authStore.me?.id ?? "anonymous")" }

    private var filteredPlayers: [Player] {
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
            .task {
                await viewModel.load(cacheKey: dataCacheKey)
            }
            .sheet(isPresented: $isCreateSheetPresented) {
                CreatePlayerSheet { payload in
                    await viewModel.create(
                        firstName: payload.firstName,
                        lastName: payload.lastName,
                        email: payload.email,
                        phone: payload.phone,
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
            .onChange(of: selectedTab) { _, newValue in
                guard newValue == .stats else { return }
                Task {
                    await statsViewModel.load(players: viewModel.players)
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
            await viewModel.load(cacheKey: dataCacheKey, forceRefresh: true)
            if selectedTab == .stats {
                await statsViewModel.load(players: viewModel.players)
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
            await viewModel.load(cacheKey: dataCacheKey, forceRefresh: true)
            if selectedTab == .stats {
                await statsViewModel.load(players: viewModel.players)
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
            await viewModel.load(cacheKey: dataCacheKey, forceRefresh: true)
            if selectedTab == .stats {
                await statsViewModel.load(players: viewModel.players)
            }
        }
    }

    private var playersSection: some View {
        Section("Effectif") {
            if filteredPlayers.isEmpty {
                Text(query.isEmpty ? "Aucun joueur" : "Aucun joueur pour cette recherche")
                    .foregroundStyle(.secondary)
            }

            ForEach(filteredPlayers) { player in
                NavigationLink {
                    PlayerDetailView(playerID: player.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.name)
                            .font(.headline)
                        let subtitle = [player.primaryPosition, player.email]
                            .compactMap { $0 }
                            .joined(separator: " • ")
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if query.isEmpty && viewModel.canLoadMorePlayers {
                Button {
                    Task { await viewModel.loadMore(cacheKey: dataCacheKey) }
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
    }

    private var tacticSection: some View {
        Section("Tactique") {
            TeamTacticCard()
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
        }
    }

    private var statsSection: some View {
        Section("Stats") {
            TeamStatsSummaryView(viewModel: statsViewModel)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
        }
    }
}

private struct TacticPoint: Codable, Identifiable {
    let id: String
    let x: CGFloat
    let y: CGFloat
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
    private enum SaveMode: String, CaseIterable, Identifiable {
        case overwrite = "Écraser l'actuelle"
        case createNew = "Créer une nouvelle"

        var id: String { rawValue }
    }

    @AppStorage("izifoot.team.tactics.json") private var tacticsJSON = ""
    @AppStorage("izifoot.team.tactics.selected") private var selectedTacticID = ""

    @State private var tactics: [SavedTactic] = []
    @State private var workingSlots: [TacticSlot] = []
    @State private var dragOffsets: [String: CGSize] = [:]
    @State private var activeDragSlotID: String?
    @State private var isSaveSheetPresented = false
    @State private var newTacticName = ""
    @State private var saveMode: SaveMode = .overwrite

    private let points: [TacticPoint] = [
        .init(id: "p1", x: 0.50, y: 0.90),
        .init(id: "p2", x: 0.20, y: 0.82),
        .init(id: "p3", x: 0.35, y: 0.82),
        .init(id: "p4", x: 0.50, y: 0.82),
        .init(id: "p5", x: 0.65, y: 0.82),
        .init(id: "p6", x: 0.80, y: 0.82),
        .init(id: "p7", x: 0.14, y: 0.72),
        .init(id: "p8", x: 0.26, y: 0.72),
        .init(id: "p9", x: 0.38, y: 0.72),
        .init(id: "p10", x: 0.50, y: 0.72),
        .init(id: "p11", x: 0.62, y: 0.72),
        .init(id: "p12", x: 0.74, y: 0.72),
        .init(id: "p13", x: 0.86, y: 0.72),
        .init(id: "p14", x: 0.10, y: 0.60),
        .init(id: "p15", x: 0.20, y: 0.60),
        .init(id: "p16", x: 0.30, y: 0.60),
        .init(id: "p17", x: 0.40, y: 0.60),
        .init(id: "p18", x: 0.50, y: 0.60),
        .init(id: "p19", x: 0.60, y: 0.60),
        .init(id: "p20", x: 0.70, y: 0.60),
        .init(id: "p21", x: 0.80, y: 0.60),
        .init(id: "p22", x: 0.90, y: 0.60),
        .init(id: "p23", x: 0.10, y: 0.48),
        .init(id: "p24", x: 0.20, y: 0.48),
        .init(id: "p25", x: 0.30, y: 0.48),
        .init(id: "p26", x: 0.40, y: 0.48),
        .init(id: "p27", x: 0.50, y: 0.48),
        .init(id: "p28", x: 0.60, y: 0.48),
        .init(id: "p29", x: 0.70, y: 0.48),
        .init(id: "p30", x: 0.80, y: 0.48),
        .init(id: "p31", x: 0.90, y: 0.48),
        .init(id: "p32", x: 0.14, y: 0.36),
        .init(id: "p33", x: 0.26, y: 0.36),
        .init(id: "p34", x: 0.38, y: 0.36),
        .init(id: "p35", x: 0.50, y: 0.36),
        .init(id: "p36", x: 0.62, y: 0.36),
        .init(id: "p37", x: 0.74, y: 0.36),
        .init(id: "p38", x: 0.86, y: 0.36),
        .init(id: "p39", x: 0.20, y: 0.24),
        .init(id: "p40", x: 0.35, y: 0.24),
        .init(id: "p41", x: 0.50, y: 0.24),
        .init(id: "p42", x: 0.65, y: 0.24),
        .init(id: "p43", x: 0.80, y: 0.24),
        .init(id: "p44", x: 0.30, y: 0.14),
        .init(id: "p45", x: 0.50, y: 0.14),
        .init(id: "p46", x: 0.70, y: 0.14),
    ]

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

            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.29, green: 0.58, blue: 0.31), Color(red: 0.36, green: 0.65, blue: 0.39)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Rectangle()
                        .fill(.white.opacity(0.42))
                        .frame(height: 2)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                    Circle()
                        .stroke(.white.opacity(0.34), lineWidth: 2)
                        .frame(width: min(proxy.size.width, proxy.size.height) * 0.22)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                    if activeDragSlotID != nil {
                        ForEach(points) { point in
                            Circle()
                                .fill(.white.opacity(0.28))
                                .frame(width: 10, height: 10)
                                .position(x: proxy.size.width * point.x, y: proxy.size.height * point.y)
                        }
                    }

                    ForEach(Array(workingSlots.enumerated()), id: \.element.id) { _, slot in
                        if let point = point(by: slot.pointID) {
                            TeamTacticPositionNode(label: positionLabel(for: point), color: uniformNodeColor)
                                .position(
                                    x: proxy.size.width * point.x + (dragOffsets[slot.id]?.width ?? 0),
                                    y: proxy.size.height * point.y + (dragOffsets[slot.id]?.height ?? 0)
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
                                                fieldSize: proxy.size
                                            )
                                        }
                                )
                        }
                    }
                }
            }
            .frame(height: 420)

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
        if let data = tacticsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([SavedTactic].self, from: data),
           !decoded.isEmpty {
            tactics = decoded
        } else {
            tactics = defaultTactics
            persistTactics()
        }

        if !tactics.contains(where: { $0.id == selectedTacticID }) {
            selectedTacticID = tactics.first?.id ?? ""
        }
        workingSlots = selectedTactic?.slots ?? tactics.first?.slots ?? []
    }

    private func apply(tactic: SavedTactic) {
        selectedTacticID = tactic.id
        workingSlots = tactic.slots
        dragOffsets = [:]
    }

    private func saveAsNewTactic() {
        let name = newTacticName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let prepared = normalized(workingSlots).map { slot in
            var copy = slot
            if let point = point(by: slot.pointID) {
                copy.label = positionLabel(for: point)
            }
            return copy
        }
        let new = SavedTactic(id: UUID().uuidString, name: name, slots: prepared)
        tactics.append(new)
        selectedTacticID = new.id
        workingSlots = new.slots
        persistTactics()
    }

    private func overwriteCurrentTactic() {
        guard let selected = selectedTactic,
              let index = tactics.firstIndex(where: { $0.id == selected.id }) else {
            saveAsNewTactic()
            return
        }

        let prepared = normalized(workingSlots).map { slot in
            var copy = slot
            if let point = point(by: slot.pointID) {
                copy.label = positionLabel(for: point)
            }
            return copy
        }

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
        tacticsJSON = json
    }

    private func handleDrop(slotID: String, startPointID: String, translation: CGSize, fieldSize: CGSize) {
        defer {
            dragOffsets[slotID] = .zero
            activeDragSlotID = nil
        }
        let start = point(by: startPointID) ?? points[0]
        let destinationX = start.x + (translation.width / max(fieldSize.width, 1))
        let destinationY = start.y + (translation.height / max(fieldSize.height, 1))

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

    private func nearestPoint(toX x: CGFloat, y: CGFloat) -> TacticPoint? {
        points.min { lhs, rhs in
            let dl = hypot(lhs.x - x, lhs.y - y)
            let dr = hypot(rhs.x - x, rhs.y - y)
            return dl < dr
        }
    }

    private func point(by id: String) -> TacticPoint? {
        points.first(where: { $0.id == id })
    }

    private func normalized(_ slots: [TacticSlot]) -> [TacticSlot] {
        slots.sorted { $0.id < $1.id }
    }

    private func resetCurrentChanges() {
        guard let selectedTactic else { return }
        workingSlots = selectedTactic.slots
        dragOffsets = [:]
        activeDragSlotID = nil
    }

    private var defaultTactics: [SavedTactic] {
        [
            SavedTactic(
                id: "default-losange",
                name: "Losange",
                slots: [
                    TacticSlot(id: "s1", label: "GK", pointID: "p1"),
                    TacticSlot(id: "s2", label: "DC", pointID: "p3"),
                    TacticSlot(id: "s3", label: "AG", pointID: "p5"),
                    TacticSlot(id: "s4", label: "AD", pointID: "p8"),
                    TacticSlot(id: "s5", label: "P", pointID: "p10"),
                ]
            ),
            SavedTactic(
                id: "default-22",
                name: "2-2",
                slots: [
                    TacticSlot(id: "s1", label: "GK", pointID: "p1"),
                    TacticSlot(id: "s2", label: "DG", pointID: "p2"),
                    TacticSlot(id: "s3", label: "DD", pointID: "p4"),
                    TacticSlot(id: "s4", label: "AG", pointID: "p9"),
                    TacticSlot(id: "s5", label: "AD", pointID: "p11"),
                ]
            ),
            SavedTactic(
                id: "default-pivot",
                name: "Pivot",
                slots: [
                    TacticSlot(id: "s1", label: "GK", pointID: "p1"),
                    TacticSlot(id: "s2", label: "DC", pointID: "p3"),
                    TacticSlot(id: "s3", label: "AG", pointID: "p6"),
                    TacticSlot(id: "s4", label: "AD", pointID: "p7"),
                    TacticSlot(id: "s5", label: "P", pointID: "p10"),
                ]
            ),
        ]
    }

    private var uniformNodeColor: Color {
        Color(red: 0.14, green: 0.43, blue: 0.89)
    }

    private func positionLabel(for point: TacticPoint) -> String {
        if point.y > 0.82 { return "GK" }

        if point.y > 0.66 {
            if point.x < 0.30 { return "DG" }
            if point.x > 0.70 { return "DD" }
            return "DC"
        }

        if point.y > 0.52 {
            if point.x < 0.30 { return "MG" }
            if point.x > 0.70 { return "MD" }
            return "MC"
        }

        if point.y > 0.34 {
            if point.x < 0.30 { return "AG" }
            if point.x > 0.70 { return "AD" }
            return "MO"
        }

        if point.x < 0.30 { return "AG" }
        if point.x > 0.70 { return "AD" }
        return "BU"
    }
}

private struct TeamTacticPositionNode: View {
    let label: String
    let color: Color

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: 50, height: 50)
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
            Text("\(viewModel.playedMatchesCount) match(s) joué(s) analysé(s)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

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
    let lastName: String
    let email: String
    let phone: String
    let primaryPosition: String
    let secondaryPosition: String?
}

struct CreatePlayerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var primaryPosition = ""
    @State private var secondaryPosition = ""

    let onSubmit: (CreatePlayerPayload) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Prénom", text: $firstName)
                TextField("Nom", text: $lastName)
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
                TextField("Téléphone", text: $phone)
                    .keyboardType(.phonePad)
                TextField("Poste principal", text: $primaryPosition)
                TextField("Poste secondaire", text: $secondaryPosition)
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
                                    firstName: firstName,
                                    lastName: lastName,
                                    email: email,
                                    phone: phone,
                                    primaryPosition: primaryPosition,
                                    secondaryPosition: secondaryPosition.isEmpty ? nil : secondaryPosition
                                )
                            )
                        }
                    }
                    .disabled(firstName.isEmpty || lastName.isEmpty || primaryPosition.isEmpty)
                }
            }
        }
    }
}
