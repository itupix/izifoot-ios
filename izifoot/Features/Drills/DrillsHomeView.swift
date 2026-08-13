import Combine
import SwiftUI

@MainActor
final class DrillsHomeViewModel: ObservableObject {
    @Published private(set) var drills: [Drill] = []
    @Published private(set) var categories: [String] = []
    @Published private(set) var tags: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var deletingDrillID: String?
    @Published var errorMessage: String?

    private let pageSize = 50
    private var nextOffset = 0
    private var canLoadMore = true
    private var isScopedToTeam = false

    private let api: IzifootAPI
    private var lastCacheKey: String?

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
        !isScopedToTeam && canLoadMore && !isLoading && !isLoadingMore
    }

    func load(cacheKey: String, teamID: String? = nil, forceRefresh: Bool = false) async {
        if lastCacheKey != cacheKey {
            lastCacheKey = cacheKey
            drills = []
            categories = []
            tags = []
            nextOffset = 0
            canLoadMore = true
            errorMessage = nil
        }

        let normalizedScopedTeamID = normalizedTeamID(teamID)
        isScopedToTeam = normalizedScopedTeamID != nil

        var hasCachedData = false
        if !forceRefresh,
           let cached = await PersistentDataCache.shared.read(DrillsHomeCachePayload.self, forKey: cacheKey) {
            drills = filteredDrills(cached.drills, teamID: normalizedScopedTeamID)
            categories = cached.categories
            tags = cached.tags
            nextOffset = cached.nextOffset
            canLoadMore = cached.canLoadMore && normalizedScopedTeamID == nil
            hasCachedData = true
            errorMessage = nil
        }

        do {
            if let normalizedScopedTeamID {
                let response = try await api.allDrills()
                drills = filteredDrills(response.items, teamID: normalizedScopedTeamID)
                categories = response.categories
                tags = response.tags
                nextOffset = 0
                canLoadMore = false
            } else {
                let response = try await api.drills(limit: pageSize, offset: 0)
                drills = response.items
                categories = response.categories
                tags = response.tags
                nextOffset = response.pagination.offset + response.pagination.returned
                canLoadMore = response.pagination.returned >= response.pagination.limit && response.pagination.returned > 0
            }
            await persistCache(forKey: cacheKey)
            errorMessage = nil
        } catch {
            if !error.isCancellationError, !hasCachedData { errorMessage = error.localizedDescription }
        }
    }

    func loadMore(cacheKey: String, teamID: String? = nil) async {
        guard normalizedTeamID(teamID) == nil else { return }
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
        teamID: String? = nil,
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
            if let normalizedScopedTeamID = normalizedTeamID(teamID) {
                if drillBelongsToScope(created, teamID: normalizedScopedTeamID) {
                    drills.insert(created, at: 0)
                    drills = filteredDrills(drills, teamID: normalizedScopedTeamID)
                } else {
                    await load(cacheKey: cacheKey, teamID: normalizedScopedTeamID, forceRefresh: true)
                    return
                }
            } else {
                drills.insert(created, at: 0)
            }
            await persistCache(forKey: cacheKey)
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func deleteDrill(id: String, teamID: String? = nil, cacheKey: String) async {
        guard deletingDrillID == nil else { return }
        deletingDrillID = id
        defer { deletingDrillID = nil }

        do {
            try await api.deleteDrill(id: id)
            if let normalizedScopedTeamID = normalizedTeamID(teamID) {
                let response = try await api.allDrills()
                drills = filteredDrills(response.items, teamID: normalizedScopedTeamID)
                categories = response.categories
                tags = response.tags
                nextOffset = 0
                canLoadMore = false
            } else {
                let reloadLimit = max(nextOffset, pageSize)
                let response = try await api.drills(limit: reloadLimit, offset: 0)
                drills = response.items
                categories = response.categories
                tags = response.tags
                nextOffset = response.pagination.offset + response.pagination.returned
                canLoadMore = response.pagination.returned >= response.pagination.limit && response.pagination.returned > 0
            }
            await persistCache(forKey: cacheKey)
            errorMessage = nil
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    private func filteredDrills(_ drills: [Drill], teamID: String?) -> [Drill] {
        guard let teamID else { return drills }
        return drills.filter { drill in
            drillBelongsToScope(drill, teamID: teamID)
        }
    }

    private func drillBelongsToScope(_ drill: Drill, teamID: String) -> Bool {
        guard let drillTeamID = normalizedTeamID(drill.teamId) else {
            return true
        }
        return drillTeamID == teamID
    }

    private func normalizedTeamID(_ teamID: String?) -> String? {
        guard let teamID = teamID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !teamID.isEmpty else {
            return nil
        }
        return teamID
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
    @EnvironmentObject private var teamScopeStore: TeamScopeStore
    @StateObject private var viewModel = DrillsHomeViewModel()
    @State private var isSheetPresented = false
    @State private var searchText = ""
    @State private var drillToDelete: Drill?
    private var dataCacheKey: String {
        "drills-home-\(authStore.me?.id ?? "anonymous")-\(teamScopeStore.selectedTeamID ?? "all")"
    }

    private var taskReloadKey: String {
        "\(dataCacheKey)-\(teamScopeStore.scopeRevision)"
    }

    var body: some View {
        NavigationStack {
            List {
                if writable && requiresSelection && teamScopeStore.selectedTeamID == nil {
                    Section {
                        Text("Sélectionnez une équipe active pour modifier les exercices.")
                            .foregroundStyle(.secondary)
                    }
                }

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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if teamScopedWritable {
                                Button(role: .destructive) {
                                    guard viewModel.deletingDrillID == nil else { return }
                                    drillToDelete = drill
                                } label: {
                                    Label(
                                        viewModel.deletingDrillID == drill.id ? "Suppression..." : "Supprimer",
                                        systemImage: "trash"
                                    )
                                }
                                .disabled(viewModel.deletingDrillID != nil)
                            }
                        }
                    }

                    if viewModel.canLoadMoreDrills {
                        Button {
                            Task {
                                await viewModel.loadMore(
                                    cacheKey: dataCacheKey,
                                    teamID: teamScopeStore.selectedTeamID
                                )
                            }
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
            .appChrome()
            .overlay(alignment: .bottomTrailing) {
                if teamScopedWritable {
                    Button {
                        isSheetPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.accentColor, in: Circle())
                            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                    .accessibilityLabel("Ajouter un exercice")
                }
            }
            .searchable(text: $searchText, prompt: "Rechercher un exercice")
            .refreshable {
                await viewModel.load(
                    cacheKey: dataCacheKey,
                    teamID: teamScopeStore.selectedTeamID,
                    forceRefresh: true
                )
            }
            .task(id: taskReloadKey) {
                await viewModel.load(cacheKey: dataCacheKey, teamID: teamScopeStore.selectedTeamID)
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
                        teamID: teamScopeStore.selectedTeamID,
                        cacheKey: dataCacheKey
                    )
                    isSheetPresented = false
                }
                .presentationDetents([.large])
            }
            .confirmationDialog(
                "Supprimer cet exercice ?",
                isPresented: Binding(
                    get: { drillToDelete != nil },
                    set: { if !$0 { drillToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Supprimer l'exercice", role: .destructive) {
                    guard let drill = drillToDelete else { return }
                    Task {
                        await viewModel.deleteDrill(
                            id: drill.id,
                            teamID: teamScopeStore.selectedTeamID,
                            cacheKey: dataCacheKey
                        )
                        drillToDelete = nil
                    }
                }
                Button("Annuler", role: .cancel) {
                    drillToDelete = nil
                }
            } message: {
                if let drill = drillToDelete {
                    Text("L'exercice \"\(drill.title)\" sera supprimé définitivement.")
                }
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

    private var writable: Bool {
        authStore.me?.role.canEditSportData == true
    }

    private var requiresSelection: Bool {
        guard let role = authStore.me?.role else { return false }
        return (role == .direction || role == .coach) && !teamScopeStore.teams.isEmpty
    }

    private var teamScopedWritable: Bool {
        writable && (!requiresSelection || teamScopeStore.selectedTeamID != nil)
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
