import Combine
import SwiftUI

@MainActor
final class PublicMatchdayViewModel: ObservableObject {
    @Published private(set) var matchday: Matchday?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI = IzifootAPI()) {
        self.api = api
    }

    func load(token: String) async {
        guard !token.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            matchday = try await api.publicMatchday(token: token)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PublicMatchdayView: View {
    @StateObject private var viewModel = PublicMatchdayViewModel()
    @State private var token = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Token de partage") {
                    TextField("Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    Button("Charger") {
                        Task {
                            await viewModel.load(token: token)
                        }
                    }
                    .disabled(token.isEmpty)
                }

                if let matchday = viewModel.matchday {
                    Section("Plateau public") {
                        LabeledContent("Date", value: DateFormatters.display(matchday.date))
                        LabeledContent("Lieu", value: matchday.lieu ?? "-")
                        if let startTime = matchday.startTime {
                            LabeledContent("Début", value: startTime)
                        }
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Chargement")
                }
            }
            .navigationTitle("Partage public")
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
