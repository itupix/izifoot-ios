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

    var canLoadMorePlayers: Bool {
        canLoadMore && !isLoading && !isLoadingMore
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await api.players(limit: pageSize, offset: 0)
            players = response.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            nextOffset = response.pagination.offset + response.pagination.returned
            canLoadMore = response.pagination.returned >= response.pagination.limit && response.pagination.returned > 0
            errorMessage = nil
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func loadMore() async {
        guard canLoadMorePlayers else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await api.players(limit: pageSize, offset: nextOffset)
            players.append(contentsOf: response.items)
            players.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            nextOffset = response.pagination.offset + response.pagination.returned
            canLoadMore = response.pagination.returned >= response.pagination.limit && response.pagination.returned > 0
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
        secondaryPosition: String?
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
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
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
    @StateObject private var viewModel = PlayersHomeViewModel()
    @StateObject private var statsViewModel = TeamStatsViewModel()
    @State private var query = ""
    @State private var isCreateSheetPresented = false
    @State private var selectedTab: TeamTab = .players

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
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Chargement")
                }
            }
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
            .navigationTitle("Mon équipe")
            .appChrome()
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $isCreateSheetPresented) {
                CreatePlayerSheet { payload in
                    await viewModel.create(
                        firstName: payload.firstName,
                        lastName: payload.lastName,
                        email: payload.email,
                        phone: payload.phone,
                        primaryPosition: payload.primaryPosition,
                        secondaryPosition: payload.secondaryPosition
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
            await viewModel.load()
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
            await viewModel.load()
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
            await viewModel.load()
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
                    Task { await viewModel.loadMore() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoadingMore {
                            ProgressView()
                        } else {
                            Text("Charger plus")
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isLoadingMore)
            }
        }
    }

    private var tacticSection: some View {
        Section("Tactique") {
            TeamTacticCard(players: viewModel.players)
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

private struct TeamTacticCard: View {
    let players: [Player]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Tactique", systemImage: "sportscourt")
                    .font(.headline)
                Spacer()
                Text("Losange")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
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

                    ForEach(Array(tacticalNodes.enumerated()), id: \.offset) { index, node in
                        TeamTacticPlayerNode(
                            title: abbreviatedName(for: node.player),
                            color: node.color
                        )
                        .position(
                            x: proxy.size.width * node.x,
                            y: proxy.size.height * node.y
                        )
                    }
                }
            }
            .frame(height: 420)

            if !benchPlayers.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Remplaçants")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
                        ForEach(Array(benchPlayers.enumerated()), id: \.offset) { index, player in
                            TeamBenchChip(
                                title: abbreviatedName(for: player),
                                color: nodeColor(for: index + tacticalNodes.count)
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var tacticalNodes: [(player: Player?, x: CGFloat, y: CGFloat, color: Color)] {
        let selected = Array(players.prefix(5))
        let layout: [(CGFloat, CGFloat)] = [
            (0.5, 0.86),
            (0.5, 0.64),
            (0.23, 0.47),
            (0.77, 0.47),
            (0.5, 0.20)
        ]
        return layout.enumerated().map { index, point in
            (selected.indices.contains(index) ? selected[index] : nil, point.0, point.1, nodeColor(for: index))
        }
    }

    private var benchPlayers: [Player] {
        Array(players.dropFirst(5))
    }

    private func abbreviatedName(for player: Player?) -> String {
        guard let player else { return "?" }
        let source = player.firstName ?? player.name
        let parts = source.split(separator: " ").map(String.init)
        guard let first = parts.first, let second = parts.dropFirst().first?.first else {
            return firstWord(in: source)
        }
        return "\(first) \(second)."
    }

    private func firstWord(in value: String) -> String {
        value.split(separator: " ").first.map(String.init) ?? value
    }

    private func nodeColor(for index: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.76, green: 0.24, blue: 0.20),
            Color(red: 0.18, green: 0.49, blue: 0.74),
            Color(red: 0.50, green: 0.23, blue: 0.88),
            Color(red: 0.89, green: 0.57, blue: 0.16),
            Color(red: 0.20, green: 0.67, blue: 0.46),
            Color(red: 0.75, green: 0.39, blue: 0.18),
            Color(red: 0.85, green: 0.27, blue: 0.58),
            Color(red: 0.17, green: 0.63, blue: 0.69)
        ]
        return palette[index % palette.count]
    }
}

private struct TeamTacticPlayerNode: View {
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(color.gradient)
                .frame(width: 58, height: 58)
                .overlay {
                    Text(initials)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.82), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let letters = title
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

private struct TeamBenchChip: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color.gradient)
                .frame(width: 14, height: 14)
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Chargement")
                    Spacer()
                }
                .padding(.vertical, 24)
            }

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
