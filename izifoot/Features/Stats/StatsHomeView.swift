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

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let players = api.allPlayers()
            async let trainings = api.allTrainings()
            async let matchdays = api.allMatchdays()
            async let drills = api.allDrills()

            playersCount = try await players.count
            trainingsCount = try await trainings.count
            matchdaysCount = try await matchdays.count
            drillsCount = try await drills.items.count
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct StatsHomeView: View {
    @StateObject private var viewModel = StatsHomeViewModel()

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
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Chargement")
                }
            }
            .navigationTitle("Stats")
            .appChrome()
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
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
