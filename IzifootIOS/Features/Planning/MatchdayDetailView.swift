import SwiftUI

@MainActor
final class MatchdayDetailViewModel: ObservableObject {
    @Published private(set) var matches: [MatchLite] = []
    @Published private(set) var isLoading = false
    @Published private(set) var publicShareURL: String?
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI = IzifootAPI()) {
        self.api = api
    }

    func load(matchdayID: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            matches = try await api.matches(matchdayID: matchdayID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func share(matchdayID: String) async {
        do {
            let share = try await api.shareMatchday(id: matchdayID)
            publicShareURL = share.url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MatchdayDetailView: View {
    let matchday: Matchday

    @StateObject private var viewModel = MatchdayDetailViewModel()

    var body: some View {
        List {
            Section("Informations") {
                LabeledContent("Date", value: DateFormatters.display(matchday.date))
                LabeledContent("Lieu", value: matchday.lieu ?? "-")
                if let startTime = matchday.startTime {
                    LabeledContent("Début", value: startTime)
                }
                if let meetingTime = matchday.meetingTime {
                    LabeledContent("Rendez-vous", value: meetingTime)
                }
            }

            Section("Matchs") {
                if viewModel.matches.isEmpty {
                    Text("Aucun match")
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.matches) { match in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(match.type)
                            .font(.headline)
                        Text("Statut: \(match.status ?? "INCONNU")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let publicShareURL = viewModel.publicShareURL {
                Section("Lien public") {
                    if let shareURL = URL(string: publicShareURL) {
                        ShareLink(item: shareURL) {
                            Label("Partager", systemImage: "square.and.arrow.up")
                        }
                    }
                    Text(publicShareURL)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Chargement")
            }
        }
        .navigationTitle("Plateau")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.share(matchdayID: matchday.id) }
                } label: {
                    Label("Partager", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task {
            await viewModel.load(matchdayID: matchday.id)
        }
        .refreshable {
            await viewModel.load(matchdayID: matchday.id)
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
