import SwiftUI

@MainActor
final class DrillsHomeViewModel: ObservableObject {
    @Published private(set) var drills: [Drill] = []
    @Published private(set) var categories: [String] = []
    @Published private(set) var tags: [String] = []
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
            let response = try await api.drills()
            drills = response.items
            categories = response.categories
            tags = response.tags
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createDrill(
        title: String,
        category: String,
        duration: Int,
        players: String,
        description: String,
        tags: [String]
    ) async {
        do {
            let created = try await api.createDrill(
                title: title,
                category: category,
                duration: duration,
                players: players,
                description: description,
                tags: tags
            )
            drills.insert(created, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DrillsHomeView: View {
    @StateObject private var viewModel = DrillsHomeViewModel()
    @State private var isSheetPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section("Exercices") {
                    if viewModel.drills.isEmpty {
                        Text("Aucun exercice")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.drills) { drill in
                        NavigationLink {
                            DrillDetailView(drillID: drill.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(drill.title)
                                    .font(.headline)
                                Text("\(drill.category) • \(drill.duration) min")
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
            .navigationTitle("Exercices")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TeamScopePicker()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSheetPresented = true
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
            .sheet(isPresented: $isSheetPresented) {
                CreateDrillSheet(defaultCategories: viewModel.categories, defaultTags: viewModel.tags) { payload in
                    await viewModel.createDrill(
                        title: payload.title,
                        category: payload.category,
                        duration: payload.duration,
                        players: payload.players,
                        description: payload.description,
                        tags: payload.tags
                    )
                    isSheetPresented = false
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

struct CreateDrillPayload {
    let title: String
    let category: String
    let duration: Int
    let players: String
    let description: String
    let tags: [String]
}

struct CreateDrillSheet: View {
    @Environment(\.dismiss) private var dismiss

    let defaultCategories: [String]
    let defaultTags: [String]
    let onSubmit: (CreateDrillPayload) async -> Void

    @State private var title = ""
    @State private var category = ""
    @State private var duration = 20
    @State private var players = "Tous"
    @State private var description = ""
    @State private var tagsCSV = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titre", text: $title)

                if !defaultCategories.isEmpty {
                    Picker("Catégorie", selection: $category) {
                        Text("Choisir").tag("")
                        ForEach(defaultCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                } else {
                    TextField("Catégorie", text: $category)
                }

                Stepper("Durée: \(duration) min", value: $duration, in: 5 ... 90, step: 5)
                TextField("Joueurs", text: $players)
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(5, reservesSpace: true)
                TextField("Tags (séparés par des virgules)", text: $tagsCSV)
            }
            .navigationTitle("Nouvel exercice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        Task {
                            let tags = tagsCSV
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            await onSubmit(
                                CreateDrillPayload(
                                    title: title,
                                    category: category,
                                    duration: duration,
                                    players: players,
                                    description: description,
                                    tags: tags
                                )
                            )
                        }
                    }
                    .disabled(title.isEmpty || category.isEmpty || description.isEmpty)
                }
            }
        }
    }
}
