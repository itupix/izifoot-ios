import SwiftUI

@MainActor
final class PlayerDetailViewModel: ObservableObject {
    @Published private(set) var player: Player?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI = IzifootAPI()) {
        self.api = api
    }

    func load(id: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            player = try await api.player(id: id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PlayerDetailView: View {
    let playerID: String

    @StateObject private var viewModel = PlayerDetailViewModel()

    var body: some View {
        List {
            if let player = viewModel.player {
                Section("Identité") {
                    LabeledContent("Nom", value: player.name)
                    if let firstName = player.firstName {
                        LabeledContent("Prénom", value: firstName)
                    }
                    if let lastName = player.lastName {
                        LabeledContent("Nom de famille", value: lastName)
                    }
                }

                Section("Sport") {
                    if let primaryPosition = player.primaryPosition {
                        LabeledContent("Poste principal", value: primaryPosition)
                    }
                    if let secondaryPosition = player.secondaryPosition {
                        LabeledContent("Poste secondaire", value: secondaryPosition)
                    }
                }

                Section("Contact") {
                    if let email = player.email {
                        LabeledContent("Email", value: email)
                    }
                    if let phone = player.phone {
                        LabeledContent("Téléphone", value: phone)
                    }
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Chargement")
            }
        }
        .navigationTitle("Joueur")
        .task {
            await viewModel.load(id: playerID)
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
