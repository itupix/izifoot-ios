import Combine
import SwiftUI

private let trainingRoleOptions = [
    "Capitaine",
    "Rangement matériel",
    "Arbitre",
    "Gardien de but",
    "Responsable échauffement",
    "Responsable hydratation",
    "Animateur cri d'équipe",
    "Coach adjoint",
]

struct TrainingRoleEntry: Identifiable, Hashable {
    let id: String
    var role: String
    var playerID: String

    init(id: String = UUID().uuidString, role: String, playerID: String) {
        self.id = id
        self.role = role
        self.playerID = playerID
    }
}

@MainActor
final class TrainingDetailViewModel: ObservableObject {
    @Published private(set) var training: Training
    @Published private(set) var players: [Player] = []
    @Published private(set) var attendance: [AttendanceRow] = []
    @Published private(set) var trainingDrills: [TrainingDrill] = []
    @Published private(set) var drillCatalog: [Drill] = []
    @Published private(set) var roleEntries: [TrainingRoleEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSavingAttendance = false
    @Published private(set) var isSavingDrills = false
    @Published private(set) var isSavingRoles = false
    @Published private(set) var isUpdatingStatus = false
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(training: Training, api: IzifootAPI? = nil) {
        self.training = training
        self.api = api ?? IzifootAPI()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let playersTask = api.players()
            async let attendanceTask = api.attendanceBySession(type: "TRAINING", sessionID: training.id)
            async let trainingDrillsTask = api.trainingDrills(trainingID: training.id)
            async let drillsTask = api.drills()
            async let rolesTask = api.trainingRoles(trainingID: training.id)

            players = try await playersTask.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            attendance = try await attendanceTask
            trainingDrills = try await trainingDrillsTask.sorted { lhs, rhs in
                lhs.order < rhs.order || (lhs.order == rhs.order && lhs.id < rhs.id)
            }
            drillCatalog = try await drillsTask.items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            roleEntries = try await rolesTask.items.map {
                TrainingRoleEntry(id: $0.id, role: $0.role, playerID: $0.playerId)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setCancelled(_ cancelled: Bool) async {
        isUpdatingStatus = true
        defer { isUpdatingStatus = false }

        do {
            training = try await api.updateTraining(id: training.id, status: cancelled ? "CANCELLED" : "PLANNED")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func savePresentPlayerIDs(_ selectedPlayerIDs: Set<String>, availablePlayers: [Player]) async {
        let previousAttendance = attendance
        let previousByPlayerID = Dictionary(uniqueKeysWithValues: attendance.map { ($0.playerId, $0.present) })
        let allPlayerIDs = Set(availablePlayers.map(\.id))
        let changedPlayerIDs = allPlayerIDs.filter { (previousByPlayerID[$0] ?? false) != selectedPlayerIDs.contains($0) }

        guard !changedPlayerIDs.isEmpty else { return }

        isSavingAttendance = true
        attendance = mergedAttendance(from: previousAttendance, selectedPlayerIDs: selectedPlayerIDs, availablePlayers: availablePlayers)

        do {
            for playerID in changedPlayerIDs {
                try await api.setAttendance(
                    sessionType: "TRAINING",
                    sessionID: training.id,
                    playerID: playerID,
                    present: selectedPlayerIDs.contains(playerID)
                )
            }
            errorMessage = nil
        } catch {
            attendance = previousAttendance
            errorMessage = error.localizedDescription
        }

        isSavingAttendance = false
    }

    func addDrill(drillID: String) async {
        guard !trainingDrills.contains(where: { $0.drillId == drillID }) else { return }
        isSavingDrills = true
        defer { isSavingDrills = false }

        do {
            let newDrill = try await api.addTrainingDrill(trainingID: training.id, drillID: drillID)
            trainingDrills = (trainingDrills + [newDrill]).sorted { lhs, rhs in
                lhs.order < rhs.order || (lhs.order == rhs.order && lhs.id < rhs.id)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeDrill(trainingDrillID: String) async {
        let previous = trainingDrills
        trainingDrills.removeAll { $0.id == trainingDrillID }
        isSavingDrills = true

        do {
            try await api.deleteTrainingDrill(trainingID: training.id, trainingDrillID: trainingDrillID)
            errorMessage = nil
        } catch {
            trainingDrills = previous
            errorMessage = error.localizedDescription
        }

        isSavingDrills = false
    }

    func moveDrill(trainingDrillID: String, direction: Int) async {
        guard let currentIndex = trainingDrills.firstIndex(where: { $0.id == trainingDrillID }) else { return }
        let newIndex = currentIndex + direction
        guard trainingDrills.indices.contains(newIndex) else { return }

        let previous = trainingDrills
        var reordered = trainingDrills
        let moved = reordered.remove(at: currentIndex)
        reordered.insert(moved, at: newIndex)
        reordered = reordered.enumerated().map { index, item in
            TrainingDrillProxy(id: item.id, trainingId: item.trainingId, drillId: item.drillId, order: index).asTrainingDrill
        }
        trainingDrills = reordered
        isSavingDrills = true

        do {
            let changed = zip(previous, reordered).filter { $0.order != $1.order }.map(\.1)
            for item in changed {
                _ = try await api.updateTrainingDrillOrder(trainingID: training.id, trainingDrillID: item.id, order: item.order)
            }
            errorMessage = nil
        } catch {
            trainingDrills = previous
            errorMessage = error.localizedDescription
        }

        isSavingDrills = false
    }

    func saveRoleEntries(_ entries: [TrainingRoleEntry]) async {
        isSavingRoles = true
        defer { isSavingRoles = false }

        do {
            let response = try await api.updateTrainingRoles(
                trainingID: training.id,
                items: entries.map { ($0.role, $0.playerID) }
            )
            roleEntries = response.items.map {
                TrainingRoleEntry(id: $0.id, role: $0.role, playerID: $0.playerId)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mergedAttendance(
        from source: [AttendanceRow],
        selectedPlayerIDs: Set<String>,
        availablePlayers: [Player]
    ) -> [AttendanceRow] {
        let availablePlayerIDs = Set(availablePlayers.map(\.id))
        var rowsByPlayerID = Dictionary(uniqueKeysWithValues: source.map { ($0.playerId, $0) })

        for playerID in availablePlayerIDs {
            if let current = rowsByPlayerID[playerID] {
                rowsByPlayerID[playerID] = AttendanceRow(
                    id: current.id,
                    sessionType: current.sessionType,
                    sessionId: current.sessionId,
                    playerId: current.playerId,
                    present: selectedPlayerIDs.contains(playerID)
                )
            } else {
                rowsByPlayerID[playerID] = AttendanceRow(
                    id: nil,
                    sessionType: "TRAINING",
                    sessionId: training.id,
                    playerId: playerID,
                    present: selectedPlayerIDs.contains(playerID)
                )
            }
        }

        return rowsByPlayerID.values.sorted { lhs, rhs in lhs.playerId < rhs.playerId }
    }
}

struct TrainingDetailView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var teamScopeStore: TeamScopeStore

    @StateObject private var viewModel: TrainingDetailViewModel
    @State private var isAttendanceSheetPresented = false
    @State private var isExercisesSheetPresented = false
    @State private var roleEditor: RoleEditorState?

    init(training: Training) {
        _viewModel = StateObject(wrappedValue: TrainingDetailViewModel(training: training))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TrainingHeaderCard(
                    training: viewModel.training,
                    writable: writable,
                    isUpdatingStatus: viewModel.isUpdatingStatus
                ) { cancelled in
                    Task {
                        await viewModel.setCancelled(cancelled)
                    }
                }

                PlayersAttendanceCard(
                    players: filteredPlayers,
                    presentPlayerIDs: presentPlayerIDs,
                    writable: writable,
                    isSaving: viewModel.isSavingAttendance
                ) {
                    isAttendanceSheetPresented = true
                }

                ExercisesCard(
                    trainingDrills: viewModel.trainingDrills,
                    drillByID: drillByID,
                    writable: writable,
                    isSaving: viewModel.isSavingDrills,
                    onAdd: {
                        isExercisesSheetPresented = true
                    },
                    onMove: { trainingDrillID, direction in
                        Task {
                            await viewModel.moveDrill(trainingDrillID: trainingDrillID, direction: direction)
                        }
                    },
                    onRemove: { trainingDrillID in
                        Task {
                            await viewModel.removeDrill(trainingDrillID: trainingDrillID)
                        }
                    }
                )

                RolesCard(
                    roles: viewModel.roleEntries,
                    playerByID: playerByID,
                    writable: writable,
                    isSaving: viewModel.isSavingRoles,
                    onAdd: {
                        roleEditor = RoleEditorState.addDefault
                    },
                    onEdit: { role in
                        roleEditor = RoleEditorState.editing(role)
                    },
                    onDelete: { roleID in
                        Task {
                            await viewModel.saveRoleEntries(viewModel.roleEntries.filter { $0.id != roleID })
                        }
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Chargement")
            }
        }
        .navigationTitle("Entraînement")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .sheet(isPresented: $isAttendanceSheetPresented) {
            AttendanceSelectionSheet(
                players: filteredPlayers,
                initiallySelectedPlayerIDs: presentPlayerIDs,
                isSaving: viewModel.isSavingAttendance
            ) { selection in
                await viewModel.savePresentPlayerIDs(selection, availablePlayers: filteredPlayers)
                isAttendanceSheetPresented = false
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isExercisesSheetPresented) {
            DrillSelectionSheet(
                drills: selectableDrills,
                selectedDrillIDs: Set(viewModel.trainingDrills.map(\.drillId)),
                isSaving: viewModel.isSavingDrills
            ) { drillID in
                await viewModel.addDrill(drillID: drillID)
            }
            .presentationDetents([.large])
        }
        .sheet(item: $roleEditor) { editor in
            RoleEditorSheet(
                editor: editor,
                availablePlayers: availablePlayersForRoleEditor(editor),
                allPresentPlayers: presentPlayers,
                playerByID: playerByID,
                isSaving: viewModel.isSavingRoles
            ) { updatedEntry in
                var nextRoles = viewModel.roleEntries
                if editor.mode == .edit {
                    if let index = nextRoles.firstIndex(where: { $0.id == updatedEntry.id }) {
                        nextRoles[index] = updatedEntry
                    }
                } else {
                    nextRoles.append(updatedEntry)
                }
                await viewModel.saveRoleEntries(nextRoles)
                roleEditor = nil
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

    private var writable: Bool {
        guard let role = authStore.me?.role else { return false }
        let requiresSelection = (role == .direction || role == .coach) && !teamScopeStore.teams.isEmpty
        return (role == .direction || role == .coach) && (!requiresSelection || teamScopeStore.selectedTeamID != nil)
    }

    private var filteredPlayers: [Player] {
        let basePlayers: [Player]
        if let selectedTeamID = teamScopeStore.selectedTeamID {
            basePlayers = viewModel.players.filter { $0.teamId == nil || $0.teamId == selectedTeamID }
        } else {
            basePlayers = viewModel.players
        }

        guard authStore.me?.role == .coach else { return basePlayers }
        let managed = Set(authStore.me?.managedTeamIds ?? [])
        return basePlayers.filter { player in
            guard let teamID = player.teamId else { return true }
            return managed.contains(teamID)
        }
    }

    private var presentPlayerIDs: Set<String> {
        Set(viewModel.attendance.filter(\.present).map(\.playerId))
    }

    private var presentPlayers: [Player] {
        filteredPlayers.filter { presentPlayerIDs.contains($0.id) }
    }

    private var playerByID: [String: Player] {
        Dictionary(uniqueKeysWithValues: filteredPlayers.map { ($0.id, $0) })
    }

    private var drillByID: [String: Drill] {
        Dictionary(uniqueKeysWithValues: viewModel.drillCatalog.map { ($0.id, $0) })
    }

    private var selectableDrills: [Drill] {
        viewModel.drillCatalog.filter { drill in
            if let selectedTeamID = teamScopeStore.selectedTeamID {
                return drill.teamId == nil || drill.teamId == selectedTeamID
            }
            return true
        }
    }

    private func availablePlayersForRoleEditor(_ editor: RoleEditorState) -> [Player] {
        let assignedElsewhere = Set(
            viewModel.roleEntries
                .filter { $0.id != editor.entry.id }
                .map(\.playerID)
        )
        return presentPlayers.filter { !assignedElsewhere.contains($0.id) || $0.id == editor.entry.playerID }
    }
}

private struct TrainingHeaderCard: View {
    let training: Training
    let writable: Bool
    let isUpdatingStatus: Bool
    let onSetCancelled: (Bool) -> Void

    var body: some View {
        DetailCard(title: "Informations") {
            LabeledContent("Date", value: DateFormatters.display(training.date))
            LabeledContent("Statut", value: statusLabel)
            if let teamID = training.teamId {
                LabeledContent("Équipe", value: teamID)
            }

            if writable {
                Button(training.status == "CANCELLED" ? "Réactiver la séance" : "Annuler la séance") {
                    onSetCancelled(training.status != "CANCELLED")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdatingStatus)
            }
        }
    }

    private var statusLabel: String {
        switch training.status {
        case "CANCELLED":
            return "Annulé"
        case "PLANNED", "PLANIFIED":
            return "Planifié"
        case let value?:
            return value
        case nil:
            return "-"
        }
    }
}

private struct PlayersAttendanceCard: View {
    let players: [Player]
    let presentPlayerIDs: Set<String>
    let writable: Bool
    let isSaving: Bool
    let onManage: () -> Void

    var body: some View {
        DetailCard(title: "Joueurs") {
            Text("\(presentPlayers.count) présent(s) sur \(players.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if presentPlayers.isEmpty {
                Text("Aucun joueur présent sélectionné.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(presentPlayers) { player in
                            VStack(spacing: 8) {
                                PlayerAvatar(player: player, size: 56)
                                Text(displayName(for: player))
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 72)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Button("Choisir les présents") {
                onManage()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!writable || isSaving)
        }
    }

    private var presentPlayers: [Player] {
        players.filter { presentPlayerIDs.contains($0.id) }
    }

    private func displayName(for player: Player) -> String {
        player.firstName ?? player.name
    }
}

private struct ExercisesCard: View {
    let trainingDrills: [TrainingDrill]
    let drillByID: [String: Drill]
    let writable: Bool
    let isSaving: Bool
    let onAdd: () -> Void
    let onMove: (String, Int) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        DetailCard(title: "Exercices") {
            if trainingDrills.isEmpty {
                Text("Aucun exercice associé à cette séance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(trainingDrills.enumerated()), id: \.element.id) { index, item in
                    let drill = drillByID[item.drillId]
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(drill?.title ?? "Exercice")
                                    .font(.body.weight(.medium))
                                Text(exerciseSubtitle(for: drill))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }

                        if writable {
                            HStack(spacing: 8) {
                                Button {
                                    onMove(item.id, -1)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .buttonStyle(.bordered)
                                .disabled(index == 0 || isSaving)

                                Button {
                                    onMove(item.id, 1)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .buttonStyle(.bordered)
                                .disabled(index == trainingDrills.count - 1 || isSaving)

                                Spacer()

                                Button("Retirer", role: .destructive) {
                                    onRemove(item.id)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isSaving)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if writable {
                Button("Ajouter / gérer les exercices") {
                    onAdd()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
    }

    private func exerciseSubtitle(for drill: Drill?) -> String {
        guard let drill else { return "Exercice indisponible" }
        return [drill.category, "\(drill.duration) min", drill.players]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

private struct RolesCard: View {
    let roles: [TrainingRoleEntry]
    let playerByID: [String: Player]
    let writable: Bool
    let isSaving: Bool
    let onAdd: () -> Void
    let onEdit: (TrainingRoleEntry) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        DetailCard(title: "Rôles") {
            if roles.isEmpty {
                Text("Aucun rôle attribué pour cette séance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(roles) { role in
                    HStack(spacing: 12) {
                        PlayerAvatar(player: playerByID[role.playerID], size: 42)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(role.role)
                                .font(.body.weight(.medium))
                            Text(playerByID[role.playerID]?.name ?? "Joueur")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if writable {
                            Button {
                                onEdit(role)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSaving)

                            Button(role: .destructive) {
                                onDelete(role.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSaving)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if writable {
                Button("Ajouter un rôle") {
                    onAdd()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
    }
}

private struct AttendanceSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let players: [Player]
    let initiallySelectedPlayerIDs: Set<String>
    let isSaving: Bool
    let onSave: (Set<String>) async -> Void

    @State private var selectedPlayerIDs: Set<String>

    init(
        players: [Player],
        initiallySelectedPlayerIDs: Set<String>,
        isSaving: Bool,
        onSave: @escaping (Set<String>) async -> Void
    ) {
        self.players = players
        self.initiallySelectedPlayerIDs = initiallySelectedPlayerIDs
        self.isSaving = isSaving
        self.onSave = onSave
        _selectedPlayerIDs = State(initialValue: initiallySelectedPlayerIDs)
    }

    var body: some View {
        NavigationStack {
            List(players) { player in
                Button {
                    toggle(player.id)
                } label: {
                    HStack(spacing: 12) {
                        PlayerAvatar(player: player, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                                .foregroundStyle(.primary)
                            if let position = player.primaryPosition, !position.isEmpty {
                                Text(position)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selectedPlayerIDs.contains(player.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Présents")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        Task {
                            await onSave(selectedPlayerIDs)
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func toggle(_ playerID: String) {
        if selectedPlayerIDs.contains(playerID) {
            selectedPlayerIDs.remove(playerID)
        } else {
            selectedPlayerIDs.insert(playerID)
        }
    }
}

private struct DrillSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let drills: [Drill]
    let selectedDrillIDs: Set<String>
    let isSaving: Bool
    let onAdd: (String) async -> Void

    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(filteredDrills) { drill in
                Button {
                    Task {
                        await onAdd(drill.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(drill.title)
                                .foregroundStyle(.primary)
                            Text([drill.category, "\(drill.duration) min", drill.players].joined(separator: " • "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedDrillIDs.contains(drill.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(selectedDrillIDs.contains(drill.id) || isSaving)
            }
            .searchable(text: $query, prompt: "Rechercher un exercice")
            .navigationTitle("Ajouter un exercice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var filteredDrills: [Drill] {
        guard !query.isEmpty else { return drills }
        let needle = query.lowercased()
        return drills.filter { drill in
            drill.title.lowercased().contains(needle)
                || drill.category.lowercased().contains(needle)
                || drill.description.lowercased().contains(needle)
                || drill.tags.contains(where: { $0.lowercased().contains(needle) })
        }
    }
}

private struct RoleEditorState: Identifiable {
    enum Mode {
        case add
        case edit
    }

    let mode: Mode
    var entry: TrainingRoleEntry

    var id: String { entry.id }

    static var addDefault: RoleEditorState {
        RoleEditorState(mode: .add, entry: TrainingRoleEntry(role: trainingRoleOptions[0], playerID: ""))
    }

    static func editing(_ entry: TrainingRoleEntry) -> RoleEditorState {
        RoleEditorState(mode: .edit, entry: entry)
    }
}

private struct RoleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let editor: RoleEditorState
    let availablePlayers: [Player]
    let allPresentPlayers: [Player]
    let playerByID: [String: Player]
    let isSaving: Bool
    let onSave: (TrainingRoleEntry) async -> Void

    @State private var role: String
    @State private var playerID: String
    @State private var rollingName = "..."
    @State private var isRandomizing = false

    init(
        editor: RoleEditorState,
        availablePlayers: [Player],
        allPresentPlayers: [Player],
        playerByID: [String: Player],
        isSaving: Bool,
        onSave: @escaping (TrainingRoleEntry) async -> Void
    ) {
        self.editor = editor
        self.availablePlayers = availablePlayers
        self.allPresentPlayers = allPresentPlayers
        self.playerByID = playerByID
        self.isSaving = isSaving
        self.onSave = onSave
        _role = State(initialValue: editor.entry.role)
        _playerID = State(initialValue: editor.entry.playerID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rôle") {
                    Picker("Rôle", selection: $role) {
                        ForEach(trainingRoleOptions, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Joueur présent") {
                    Picker("Joueur", selection: $playerID) {
                        Text("Choisir un joueur").tag("")
                        ForEach(candidatePlayers) { player in
                            Text(player.name).tag(player.id)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Button {
                        randomizePlayer()
                    } label: {
                        HStack {
                            Image(systemName: "dice")
                            Text(isRandomizing ? rollingName : "Tirage au sort")
                        }
                    }
                    .disabled(candidatePlayers.isEmpty || isSaving)
                }
            }
            .navigationTitle(editor.mode == .add ? "Ajouter un rôle" : "Modifier le rôle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editor.mode == .add ? "Ajouter" : "Enregistrer") {
                        Task {
                            await onSave(TrainingRoleEntry(id: editor.entry.id, role: role, playerID: playerID))
                        }
                    }
                    .disabled(playerID.isEmpty || isSaving)
                }
            }
        }
    }

    private var candidatePlayers: [Player] {
        var candidates = availablePlayers
        if !playerID.isEmpty, candidates.contains(where: { $0.id == playerID }) == false, let current = playerByID[playerID] {
            candidates.append(current)
        }
        return candidates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func randomizePlayer() {
        guard !candidatePlayers.isEmpty else { return }
        isRandomizing = true

        Task {
            for _ in 0 ..< 12 {
                if let random = candidatePlayers.randomElement() {
                    rollingName = random.name
                    playerID = random.id
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
            isRandomizing = false
        }
    }
}

private struct PlayerAvatar: View {
    let player: Player?
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
    }

    private var initials: String {
        let source = player?.name ?? "?"
        let parts = source.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

private struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TrainingDrillProxy {
    let id: String
    let trainingId: String?
    let drillId: String
    let order: Int

    var asTrainingDrill: TrainingDrill {
        .init(id: id, trainingId: trainingId, drillId: drillId, order: order)
    }
}

private extension TrainingDrill {
    init(id: String, trainingId: String?, drillId: String, order: Int) {
        self = TrainingDrillProxy(id: id, trainingId: trainingId, drillId: drillId, order: order).asTrainingDrill
    }
}
