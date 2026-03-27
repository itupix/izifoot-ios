import SwiftUI

@MainActor
final class ClubHomeViewModel: ObservableObject {
    @Published private(set) var club: Club?
    @Published private(set) var teams: [Team] = []
    @Published private(set) var coaches: [Coach] = []
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
            async let clubTask = api.myClub()
            async let teamsTask = api.teams()
            async let coachesTask = api.clubCoaches()
            club = try await clubTask
            teams = try await teamsTask
            coaches = try await coachesTask
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTeam(name: String, category: String?, format: String?) async {
        do {
            let newTeam = try await api.createTeam(name: name, category: category, format: format)
            teams.insert(newTeam, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ClubHomeView: View {
    @StateObject private var viewModel = ClubHomeViewModel()
    @State private var isCreateTeamSheetPresented = false

    var body: some View {
        NavigationStack {
            List {
                if let club = viewModel.club {
                    Section("Club") {
                        Label(club.name, systemImage: "building.2.crop.circle")
                    }
                }

                Section("Equipes") {
                    ForEach(viewModel.teams) { team in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(team.name)
                                .font(.headline)
                            Text([team.category, team.format].compactMap { $0 }.joined(separator: " • "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Coachs") {
                    ForEach(viewModel.coaches) { coach in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(coach.email ?? "Coach")
                                .font(.headline)
                            let fullName = [coach.firstName, coach.lastName]
                                .compactMap { $0 }
                                .joined(separator: " ")
                            if !fullName.isEmpty {
                                Text(fullName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Chargement")
                }
            }
            .navigationTitle("Mon club")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TeamScopePicker()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreateTeamSheetPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await viewModel.load()
            }
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $isCreateTeamSheetPresented) {
                CreateTeamSheet { name, category, format in
                    await viewModel.createTeam(name: name, category: category, format: format)
                    isCreateTeamSheetPresented = false
                }
                .presentationDetents([.medium])
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

struct CreateTeamSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = ""
    @State private var format = ""

    let onSubmit: (String, String?, String?) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: $name)
                TextField("Catégorie", text: $category)
                TextField("Format (5v5, 8v8, 11v11)", text: $format)
            }
            .navigationTitle("Nouvelle équipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        Task {
                            await onSubmit(
                                name,
                                category.isEmpty ? nil : category,
                                format.isEmpty ? nil : format
                            )
                        }
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
