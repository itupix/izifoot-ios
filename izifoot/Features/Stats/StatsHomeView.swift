import Combine
import SwiftUI

@MainActor
final class StatsHomeViewModel: ObservableObject {
    @Published private(set) var playersCount = 0
    @Published private(set) var trainingsCount = 0
    @Published private(set) var matchdaysCount = 0
    @Published private(set) var drillsCount = 0
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
    }

    func load(cacheKey: String, forceRefresh: Bool = false) async {
        var hasCachedData = false
        if !forceRefresh,
           let cached = await PersistentDataCache.shared.read(StatsHomeCachePayload.self, forKey: cacheKey) {
            playersCount = cached.playersCount
            trainingsCount = cached.trainingsCount
            matchdaysCount = cached.matchdaysCount
            drillsCount = cached.drillsCount
            hasCachedData = true
            errorMessage = nil
        }

        do {
            async let players = api.allPlayers()
            async let trainings = api.allTrainings()
            async let matchdays = api.allMatchdays()
            async let drills = api.allDrills()

            playersCount = try await players.count
            trainingsCount = try await trainings.count
            matchdaysCount = try await matchdays.count
            drillsCount = try await drills.items.count
            await PersistentDataCache.shared.write(
                StatsHomeCachePayload(
                    playersCount: playersCount,
                    trainingsCount: trainingsCount,
                    matchdaysCount: matchdaysCount,
                    drillsCount: drillsCount
                ),
                forKey: cacheKey
            )
            errorMessage = nil
        } catch {
            if !error.isCancellationError, !hasCachedData { errorMessage = error.localizedDescription }
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
                Section("Vue d'ensemble") {
                    LabeledContent("Joueurs", value: "\(viewModel.playersCount)")
                    LabeledContent("Entraînements", value: "\(viewModel.trainingsCount)")
                    LabeledContent("Plateaux", value: "\(viewModel.matchdaysCount)")
                    LabeledContent("Exercices", value: "\(viewModel.drillsCount)")
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await viewModel.load(cacheKey: dataCacheKey)
            }
            .refreshable {
                await viewModel.load(cacheKey: dataCacheKey, forceRefresh: true)
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
