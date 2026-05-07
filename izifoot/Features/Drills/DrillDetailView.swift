import Combine
import SwiftUI

@MainActor
final class DrillDetailViewModel: ObservableObject {
    @Published private(set) var drill: Drill?
    @Published private(set) var diagram: Diagram?
    @Published private(set) var isLoading = false
    @Published private(set) var isSavingDiagram = false
    @Published private(set) var isGeneratingDiagram = false
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI? = nil) {
        self.api = api ?? IzifootAPI()
    }

    func load(drillID: String, trainingDrillID: String?) async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let drillTask = api.drill(id: drillID)
            let diagrams: [Diagram]
            if let trainingDrillID {
                diagrams = try await api.trainingDrillDiagrams(trainingDrillID: trainingDrillID)
            } else {
                diagrams = try await api.drillDiagrams(drillID: drillID)
            }

            drill = try await drillTask
            diagram = diagrams.first
            errorMessage = nil
        } catch {
            if !error.isCancellationError {
                errorMessage = error.localizedDescription
            }
        }
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
    @State private var isEditorPresented = false
    @State private var isViewerPresented = false
    @State private var editorData = DiagramData.empty

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if writable && requiresSelection && teamScopeStore.selectedTeamID == nil {
                    DrillDetailCard {
                        Text("Selectionnez une equipe active pour modifier le diagramme de cet exercice.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let drill = viewModel.drill {
                    DrillDetailCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(drill.category)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                drillStatChip(title: "Duree", value: "\(drill.duration) min")
                                drillStatChip(title: "Joueurs", value: drill.players)
                            }

                            if !drill.tags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(drill.tags, id: \.self) { tag in
                                            Text(tag)
                                                .font(.caption.weight(.medium))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(uiColor: .tertiarySystemBackground), in: Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }

                    DrillDetailCard(title: "Description") {
                        if drill.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Aucune description renseignee.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(drill.description)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }

                    DrillDetailCard(title: "Diagramme") {
                        if let diagram = viewModel.diagram {
                            DiagramPlayerView(data: diagram.data, minHeight: 300)
                                .padding(.bottom, 4)

                            HStack(spacing: 10) {
                                Button("Agrandir") {
                                    isViewerPresented = true
                                }
                                .buttonStyle(.bordered)

                                if teamScopedWritable {
                                    Button("Modifier") {
                                        editorData = diagram.data
                                        isEditorPresented = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        } else {
                            Text("Aucun diagramme disponible.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if teamScopedWritable {
                                Button("Creer un diagramme") {
                                    editorData = .empty
                                    isEditorPresented = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        if teamScopedWritable {
                            HStack(spacing: 10) {
                                Button {
                                    Task {
                                        await viewModel.generateDiagram(
                                            drillID: drillID,
                                            trainingDrillID: trainingDrillID,
                                            objective: drill.description
                                        )
                                    }
                                } label: {
                                    if viewModel.isGeneratingDiagram {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        Label("Generer avec IA", systemImage: "sparkles")
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isGeneratingDiagram)
                            }
                            .padding(.top, 2)
                        }
                    }

                    DrillDetailCard(title: "Materiel") {
                        let materials = viewModel.diagram?.data.materialSummary() ?? []
                        if materials.isEmpty {
                            Text("Le materiel sera derive automatiquement du diagramme.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(materials, id: \.self) { material in
                                    Label(material, systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(viewModel.drill?.title ?? "Exercice")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isLoading && viewModel.drill == nil {
                ProgressView("Chargement")
            }
        }
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

    private func drillStatChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
