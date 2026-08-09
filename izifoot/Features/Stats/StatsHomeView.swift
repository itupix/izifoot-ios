import Combine
import SwiftUI

@MainActor
final class StatsHomeViewModel: ObservableObject {
    @Published private(set) var playersCount = 0
    @Published private(set) var trainingsCount = 0
    @Published private(set) var matchdaysCount = 0
    @Published private(set) var drillsCount = 0
    @Published private(set) var seasons: [Season] = []
    @Published var selectedSeasonID = ""
    @Published private(set) var seasonLabel = ""
    @Published private(set) var seasonRangeLabel = ""
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI = IzifootAPI()) {
        self.api = api
    }

    private struct StatsHomeCachePayload: Codable {
        let playersCount: Int
        let trainingsCount: Int
        let matchdaysCount: Int
        let drillsCount: Int
        let seasons: [Season]
        let selectedSeasonID: String
        let seasonLabel: String
        let seasonRangeLabel: String
    }

    func load(cacheKey: String, forceRefresh: Bool = false, refreshSeasonCatalog: Bool = false) async {
        var hasCachedData = false
        if !forceRefresh,
           let cached = await PersistentDataCache.shared.read(StatsHomeCachePayload.self, forKey: cacheKey) {
            playersCount = cached.playersCount
            trainingsCount = cached.trainingsCount
            matchdaysCount = cached.matchdaysCount
            drillsCount = cached.drillsCount
            seasons = cached.seasons
            selectedSeasonID = cached.selectedSeasonID
            seasonLabel = cached.seasonLabel
            seasonRangeLabel = cached.seasonRangeLabel
            hasCachedData = true
            errorMessage = nil
        }

        do {
            if refreshSeasonCatalog || seasons.isEmpty {
                let club = try await api.myClub()
                do {
                    let fetchedSeasons = try await api.allClubSeasons()
                    seasons = Self.mergedSeasons(fetchedSeasons, currentSeason: club.currentSeason)
                    if selectedSeasonID.isEmpty || !seasons.contains(where: { $0.id == selectedSeasonID }) {
                        selectedSeasonID = club.currentSeason?.id ?? seasons.first?.id ?? ""
                    }
                } catch {
                    if error.isMissingClubSeasonsEndpoint {
                        seasons = Self.mergedSeasons([], currentSeason: club.currentSeason)
                        if selectedSeasonID.isEmpty || !seasons.contains(where: { $0.id == selectedSeasonID }) {
                            selectedSeasonID = club.currentSeason?.id ?? seasons.first?.id ?? ""
                        }
                    } else {
                        throw error
                    }
                }
            }

            let selectedSeason = seasons.first(where: { $0.id == selectedSeasonID })
            let effectiveSeasonID = selectedSeason?.id
            async let players = api.allPlayers()
            async let trainings = api.allTrainings(seasonID: effectiveSeasonID)
            async let matchdays = api.allMatchdays(seasonID: effectiveSeasonID)
            async let drills = api.allDrills()

            playersCount = try await players.count
            trainingsCount = try await trainings.count
            matchdaysCount = try await matchdays.count
            drillsCount = try await drills.items.count
            seasonLabel = selectedSeason?.label ?? ""
            seasonRangeLabel = selectedSeason.map { SeasonSupport.rangeLabel(for: $0) } ?? ""
            await PersistentDataCache.shared.write(
                StatsHomeCachePayload(
                    playersCount: playersCount,
                    trainingsCount: trainingsCount,
                    matchdaysCount: matchdaysCount,
                    drillsCount: drillsCount,
                    seasons: seasons,
                    selectedSeasonID: selectedSeasonID,
                    seasonLabel: seasonLabel,
                    seasonRangeLabel: seasonRangeLabel
                ),
                forKey: cacheKey
            )
            errorMessage = nil
        } catch {
            if !error.isCancellationError, !hasCachedData { errorMessage = error.localizedDescription }
        }
    }

    private static func mergedSeasons(_ seasons: [Season], currentSeason: Season?) -> [Season] {
        var merged = seasons
        if let currentSeason,
           !merged.contains(where: { $0.id == currentSeason.id }) {
            merged.insert(currentSeason, at: 0)
        }
        return merged.sorted { lhs, rhs in
            lhs.startDate > rhs.startDate
        }
    }
}

struct StatsHomeView: View {
    @EnvironmentObject private var authStore: AuthStore
    @StateObject private var viewModel = StatsHomeViewModel()
    private var dataCacheKey: String { "stats-home-\(authStore.me?.id ?? "anonymous")" }

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.seasons.isEmpty {
                    Section {
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
                                Text("Saison")
                                Spacer()
                                Text(viewModel.seasonLabel.isEmpty ? "Choisir une saison" : viewModel.seasonLabel)
                                    .foregroundStyle(.primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Vue d'ensemble") {
                    LabeledContent("Joueurs", value: "\(viewModel.playersCount)")
                    LabeledContent("Entraînements", value: "\(viewModel.trainingsCount)")
                    LabeledContent("Plateaux", value: "\(viewModel.matchdaysCount)")
                    LabeledContent("Exercices", value: "\(viewModel.drillsCount)")
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
            .appChrome()
            .task {
                await viewModel.load(cacheKey: dataCacheKey, refreshSeasonCatalog: true)
            }
            .onChange(of: viewModel.selectedSeasonID) { _ in
                Task {
                    await viewModel.load(cacheKey: dataCacheKey, forceRefresh: true)
                }
            }
            .refreshable {
                await viewModel.load(cacheKey: dataCacheKey, forceRefresh: true, refreshSeasonCatalog: true)
            }
            .alert("Erreur", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { _ in viewModel.errorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}
