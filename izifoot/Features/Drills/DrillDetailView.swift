import Combine
import SwiftUI

@MainActor
final class DrillDetailViewModel: ObservableObject {
    @Published private(set) var drill: Drill?
    @Published private(set) var diagram: Diagram?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingDiagram = false
    @Published private(set) var loadErrorMessage: String?
    @Published private(set) var diagramErrorMessage: String?
    @Published private(set) var isSavingDiagram = false
    @Published private(set) var isGeneratingDiagram = false
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI? = nil) {
        self.api = api ?? IzifootAPI()
    }

    func load(drillID: String, trainingDrillID: String?) async {
        async let details: Void = loadDrill(drillID: drillID)
        async let illustration: Void = loadDiagram(drillID: drillID, trainingDrillID: trainingDrillID)
        _ = await (details, illustration)
    }

    func loadDrill(drillID: String) async {
        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }
        do {
            drill = try await api.drill(id: drillID)
        } catch {
            if !error.isCancellationError { loadErrorMessage = error.localizedDescription }
        }
    }

    func loadDiagram(drillID: String, trainingDrillID: String?) async {
        isLoadingDiagram = true
        diagramErrorMessage = nil
        defer { isLoadingDiagram = false }
        do {
            let diagrams: [Diagram]
            if let trainingDrillID {
                diagrams = try await api.trainingDrillDiagrams(trainingDrillID: trainingDrillID)
            } else {
                diagrams = try await api.drillDiagrams(drillID: drillID)
            }
            diagram = diagrams.first
        } catch {
            if !error.isCancellationError { diagramErrorMessage = error.localizedDescription }
        }
    }

    func applyUpdatedDrill(_ updated: Drill) {
        guard updated.id == drill?.id else { return }
        drill = updated
    }

    func saveDiagram(_ data: DiagramData, drillID: String, trainingDrillID: String?) async -> Bool {
        isSavingDiagram = true
        defer { isSavingDiagram = false }

        do {
            if let existingDiagramID = diagram?.id {
                diagram = try await api.updateDiagram(id: existingDiagramID, title: "Diagramme", data: data)
            } else if let trainingDrillID {
                diagram = try await api.createTrainingDrillDiagram(trainingDrillID: trainingDrillID, data: data)
            } else {
                diagram = try await api.createDrillDiagram(drillID: drillID, data: data)
            }
            diagramErrorMessage = nil
            errorMessage = nil
            return true
        } catch {
            if !error.isCancellationError {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    func generateDiagram(drillID: String, trainingDrillID: String?, objective: String?) async {
        isGeneratingDiagram = true
        defer { isGeneratingDiagram = false }

        do {
            if let trainingDrillID {
                diagram = try await api.generateAITrainingDrillDiagram(trainingDrillID: trainingDrillID, objective: objective)
            } else {
                diagram = try await api.generateAIDrillDiagram(drillID: drillID, objective: objective)
            }
            diagramErrorMessage = nil
            errorMessage = nil
        } catch {
            if !error.isCancellationError {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct DrillDetailView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var teamScopeStore: TeamScopeStore

    let drillID: String
    var trainingDrillID: String? = nil

    @StateObject private var viewModel = DrillDetailViewModel()
    @State private var isDrillEditorPresented = false
    @State private var isEditorPresented = false
    @State private var isViewerPresented = false
    @State private var editorData = DiagramData.empty

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let drill = viewModel.drill {
                    drillHeader(drill)

                    if let message = viewModel.loadErrorMessage {
                        loadingError(title: "La fiche n’a pas pu être actualisée.", message: message) {
                            await viewModel.loadDrill(drillID: drillID)
                        }
                    }

                    if writable && requiresSelection && teamScopeStore.selectedTeamID == nil {
                        Label("Sélectionnez une équipe active pour modifier la fiche ou le diagramme.", systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    DrillDetailCard(title: "Description") {
                        Text(drill.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "Aucune description." : drill.description)
                            .font(.body)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }

                    diagramSection(drill)

                    let materials = viewModel.diagram?.data.materialSummary() ?? []
                    if !materials.isEmpty {
                        DrillDetailCard(title: "Matériel") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(materials, id: \.self) { material in
                                    Label(material, systemImage: "checkmark.circle")
                                }
                            }
                            .font(.subheadline)
                        }
                    }
                } else if viewModel.isLoading {
                    ProgressView("Chargement de l’exercice…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if let message = viewModel.loadErrorMessage {
                    loadingError(title: "Impossible de charger l’exercice", message: message) {
                        await viewModel.loadDrill(drillID: drillID)
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Exercice")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: taskIdentifier) {
            await viewModel.load(drillID: drillID, trainingDrillID: trainingDrillID)
        }
        .alert("Erreur", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { _ in viewModel.errorMessage = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .drillDidUpdate)) { notification in
            if let updated = notification.object as? Drill {
                viewModel.applyUpdatedDrill(updated)
            }
        }
        .sheet(isPresented: $isDrillEditorPresented) {
            if let drill = viewModel.drill {
                EditDrillSheet(drill: drill) { updated in
                    viewModel.applyUpdatedDrill(updated)
                    isDrillEditorPresented = false
                }
            }
        }
        .fullScreenCover(isPresented: $isEditorPresented) {
            NavigationStack {
                DiagramEditorView(data: $editorData)
                    .padding(16)
                    .navigationTitle(viewModel.diagram == nil ? "Nouveau diagramme" : "Modifier le diagramme")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annuler") {
                                isEditorPresented = false
                            }
                            .disabled(viewModel.isSavingDiagram)
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                Task {
                                    let didSave = await viewModel.saveDiagram(
                                        editorData,
                                        drillID: drillID,
                                        trainingDrillID: trainingDrillID
                                    )
                                    if didSave {
                                        isEditorPresented = false
                                    }
                                }
                            } label: {
                                if viewModel.isSavingDiagram {
                                    ProgressView()
                                } else {
                                    Text("Enregistrer")
                                }
                            }
                            .disabled(viewModel.isSavingDiagram)
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $isViewerPresented) {
            NavigationStack {
                ScrollView {
                    if let diagram = viewModel.diagram {
                        DiagramPlayerView(data: diagram.data, minHeight: 420)
                            .padding(16)
                    }
                }
                .navigationTitle("Diagramme")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") {
                            isViewerPresented = false
                        }
                    }
                }
            }
        }
    }

    private func drillHeader(_ drill: Drill) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(drill.title)
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(DrillCategory.label(for: drill.category))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: Capsule())

            if !drill.tags.isEmpty {
                Text(drill.tags.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if teamScopedWritable {
                Button {
                    isDrillEditorPresented = true
                } label: {
                    Label("Modifier la fiche", systemImage: "square.and.pencil")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func diagramSection(_ drill: Drill) -> some View {
        DrillDetailCard(title: "Diagramme") {
            if let diagram = viewModel.diagram {
                DiagramPlayerView(data: diagram.data, minHeight: 280)
                Button {
                    isViewerPresented = true
                } label: {
                    Label("Agrandir", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                if teamScopedWritable {
                    Button {
                        editorData = diagram.data
                        isEditorPresented = true
                    } label: {
                        Label("Modifier le diagramme", systemImage: "pencil")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isGeneratingDiagram)
                }
            }

            if viewModel.isLoadingDiagram {
                ProgressView("Chargement du diagramme…")
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if let message = viewModel.diagramErrorMessage {
                loadingError(title: "Le diagramme n’a pas pu être chargé.", message: message) {
                    await viewModel.loadDiagram(drillID: drillID, trainingDrillID: trainingDrillID)
                }
            } else {
                if viewModel.diagram == nil {
                    Text("Pas encore de diagramme.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if teamScopedWritable {
                        Button {
                            editorData = .empty
                            isEditorPresented = true
                        } label: {
                            Label("Créer un diagramme", systemImage: "plus")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isGeneratingDiagram)
                    }
                }

                if viewModel.diagram?.data.materialSummary().isEmpty == true {
                    Text("Aucun matériel indiqué dans le diagramme.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if viewModel.diagram == nil {
                    Text("Ajoutez un diagramme pour identifier le matériel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if teamScopedWritable {
                    Button {
                        Task {
                            await viewModel.generateDiagram(
                                drillID: drillID,
                                trainingDrillID: trainingDrillID,
                                objective: drill.description
                            )
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isGeneratingDiagram { ProgressView() }
                            Label(viewModel.isGeneratingDiagram ? "Création en cours…"
                                  : viewModel.diagram == nil ? "Créer avec l’IA" : "Générer une nouvelle proposition",
                                  systemImage: "sparkles")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isGeneratingDiagram)
                }
            }
        }
    }

    private func loadingError(title: String, message: String, retry: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.circle")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await retry() }
            } label: {
                Label("Réessayer", systemImage: "arrow.clockwise")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var taskIdentifier: String {
        "\(drillID)::\(trainingDrillID ?? "catalog")"
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
}

extension Notification.Name {
    static let drillDidUpdate = Notification.Name("izifoot.drillDidUpdate")
}

@MainActor
final class DrillEditViewModel: ObservableObject {
    @Published var title: String
    @Published var description: String
    @Published var category: String
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?
    private let persist: (String, String, String) async throws -> Drill

    init(drill: Drill, persist: @escaping (String, String, String) async throws -> Drill) {
        title = drill.title
        description = drill.description
        category = drill.category
        self.persist = persist
    }

    var validationError: String? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTitle.isEmpty || cleanTitle.utf16.count > 100 { return "Le titre doit contenir entre 1 et 100 caractères." }
        if cleanDescription.isEmpty || cleanDescription.utf16.count > 2000 { return "La description doit contenir entre 1 et 2 000 caractères." }
        if !DrillCategory.values.contains(category) { return "Choisissez une catégorie valide." }
        return nil
    }

    func save() async -> Drill? {
        guard !isSaving else { return nil }
        if let validationError {
            errorMessage = validationError
            return nil
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            return try await persist(
                title.trimmingCharacters(in: .whitespacesAndNewlines),
                description.trimmingCharacters(in: .whitespacesAndNewlines),
                category
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

private struct EditDrillSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DrillEditViewModel
    let onSaved: (Drill) -> Void

    init(drill: Drill, onSaved: @escaping (Drill) -> Void) {
        self.onSaved = onSaved
        _viewModel = StateObject(wrappedValue: DrillEditViewModel(drill: drill) { title, description, category in
            let updated = try await IzifootAPI().updateDrill(id: drill.id, title: title, description: description, category: category)
            await PersistentDataCache.shared.removeAll(withKeySuffix: ":drill-contract-v2")
            NotificationCenter.default.post(name: .drillDidUpdate, object: updated)
            return updated
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fiche de l’exercice") {
                    TextField("Titre", text: $viewModel.title)
                    TextField("Description", text: $viewModel.description, axis: .vertical)
                        .lineLimit(5, reservesSpace: true)
                    Picker("Catégorie", selection: $viewModel.category) {
                        ForEach(DrillCategory.values, id: \.self) { category in
                            Text(DrillCategory.label(for: category)).tag(category)
                        }
                    }
                }
                .disabled(viewModel.isSaving)
                if let message = viewModel.errorMessage ?? viewModel.validationError {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Modifier la fiche")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(viewModel.isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }.disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let updated = await viewModel.save() { onSaved(updated) }
                        }
                    } label: {
                        if viewModel.isSaving { ProgressView() } else { Text("Enregistrer") }
                    }
                    .disabled(viewModel.isSaving || viewModel.validationError != nil)
                }
            }
        }
    }
}

private struct DrillDetailCard<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}
