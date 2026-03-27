import SwiftUI

@MainActor
final class PlayersHomeViewModel: ObservableObject {
    @Published private(set) var players: [Player] = []
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
            players = try await api.players().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }
}

struct PlayersHomeView: View {
    @StateObject private var viewModel = PlayersHomeViewModel()
    @State private var query = ""
    @State private var isCreateSheetPresented = false

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
            .lowercased()
            return haystack.contains(query.lowercased())
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Effectif") {
                    if filteredPlayers.isEmpty {
                        Text("Aucun joueur")
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
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Chargement")
                }
            }
            .navigationTitle("Mon équipe")
            .searchable(text: $query, prompt: "Rechercher un joueur")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TeamScopePicker()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreateSheetPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                await viewModel.load()
            }
            .refreshable {
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
        }
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
