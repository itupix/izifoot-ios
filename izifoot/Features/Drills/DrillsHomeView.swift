import Combine
import SwiftUI

@MainActor
final class DrillsHomeViewModel: ObservableObject {
    @Published private(set) var drills: [Drill] = []
    @Published private(set) var categories: [String] = []
    @Published private(set) var tags: [String] = []
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

    private struct DrillsHomeCachePayload: Codable {
        let drills: [Drill]
        let categories: [String]
        let tags: [String]
        let nextOffset: Int
        let canLoadMore: Bool
    }

    var canLoadMoreDrills: Bool {
        canLoadMore && !isLoading && !isLoadingMore
    }

    func load(cacheKey: String, forceRefresh: Bool = false) async {
        var hasCachedData = false
        if !forceRefresh,
           let cached = await PersistentDataCache.shared.read(DrillsHomeCachePayload.self, forKey: cacheKey) {
            drills = cached.drills
            categories = cached.categories
            tags = cached.tags
            nextOffset = cached.nextOffset
            canLoadMore = cached.canLoadMore
            hasCachedData = true
            errorMessage = nil
        }

        do {
            let response = try await api.drills(limit: pageSize, offset: 0)
            drills = response.items
            categories = response.categories
            tags = response.tags
            nextOffset = response.pagination.offset + response.pagination.returned
            canLoadMore = response.pagination.returned >= response.pagination.limit && response.pagination.returned > 0
            await persistCache(forKey: cacheKey)
            errorMessage = nil
        } catch {
            if !error.isCancellationError, !hasCachedData { errorMessage = error.localizedDescription }
        }
    }

    func loadMore(cacheKey: String) async {
        guard canLoadMoreDrills else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await api.drills(limit: pageSize, offset: nextOffset)
            drills.append(contentsOf: response.items)
            categories = Array(Set(categories).union(response.categories)).sorted()
            tags = Array(Set(tags).union(response.tags)).sorted()
            nextOffset = response.pagination.offset + response.pagination.returned
            canLoadMore = response.pagination.returned >= response.pagination.limit && response.pagination.returned > 0
            await persistCache(forKey: cacheKey)
            errorMessage = nil
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func createDrill(
        title: String,
        category: String,
        duration: Int,
        players: String,
        description: String,
        tags: [String],
        cacheKey: String
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
            await persistCache(forKey: cacheKey)
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    private func persistCache(forKey cacheKey: String) async {
        await PersistentDataCache.shared.write(
            DrillsHomeCachePayload(
                drills: drills,
                categories: categories,
                tags: tags,
                nextOffset: nextOffset,
                canLoadMore: canLoadMore
            ),
            forKey: cacheKey
        )
    }
}

struct DrillsHomeView: View {
    @EnvironmentObject private var authStore: AuthStore
    @StateObject private var viewModel = DrillsHomeViewModel()
    @State private var isSheetPresented = false
    @State private var searchText = ""
    private var dataCacheKey: String { "drills-home-\(authStore.me?.id ?? "anonymous")" }

    var body: some View {
        NavigationStack {
            List {
                Section("Exercices") {
                    if filteredDrills.isEmpty {
                        Text(searchText.isEmpty ? "Aucun exercice" : "Aucun exercice pour cette recherche")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(filteredDrills) { drill in
                        NavigationLink {
                            DrillDetailView(drillID: drill.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(drill.title)
                                    .font(.headline)
                                Text(drill.category)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if viewModel.canLoadMoreDrills {
                        Button {
                            Task { await viewModel.loadMore(cacheKey: dataCacheKey) }
                        } label: {
                            HStack {
                                Spacer()
                                Text(viewModel.isLoadingMore ? "Chargement..." : "Charger plus")
                                Spacer()
                            }
                        }
                        .disabled(viewModel.isLoadingMore)
                    }
                }
            }
            .navigationTitle("Exercices")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Rechercher un exercice")
            .refreshable {
                await viewModel.load(cacheKey: dataCacheKey, forceRefresh: true)
            }
            .task {
                await viewModel.load(cacheKey: dataCacheKey)
            }
            .sheet(isPresented: $isSheetPresented) {
                CreateDrillSheet(defaultCategories: viewModel.categories, defaultTags: viewModel.tags) { payload in
                    await viewModel.createDrill(
                        title: payload.title,
                        category: payload.category,
                        duration: payload.duration,
                        players: payload.players,
                        description: payload.description,
                        tags: payload.tags,
                        cacheKey: dataCacheKey
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

    private var filteredDrills: [Drill] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return viewModel.drills
        }

        let needle = searchText
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return viewModel.drills.filter { drill in
            drill.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle)
                || drill.category.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle)
                || drill.description.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle)
                || drill.tags.contains {
                    $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle)
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
