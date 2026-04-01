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
    @Published private(set) var trainingIntentByPlayerID: [String: String] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isSavingAttendance = false
    @Published private(set) var isSavingDrills = false
    @Published private(set) var isSavingRoles = false
    @Published private(set) var isUpdatingStatus = false
    @Published private(set) var isDeleting = false
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
            async let playersTask = api.allPlayers()
            async let attendanceTask = api.allAttendanceBySession(type: "TRAINING", sessionID: training.id)
            async let trainingDrillsTask = api.trainingDrills(trainingID: training.id)
            async let drillsTask = api.allDrills()
            async let rolesTask = api.trainingRoles(trainingID: training.id)
            async let intentsTask = api.trainingIntent(trainingID: training.id)

            players = try await playersTask.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            attendance = try await attendanceTask
            trainingDrills = try await trainingDrillsTask.sorted { lhs, rhs in
                lhs.order < rhs.order || (lhs.order == rhs.order && lhs.id < rhs.id)
            }
            drillCatalog = try await drillsTask.items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            roleEntries = try await rolesTask.items.map {
                TrainingRoleEntry(id: $0.id, role: $0.role, playerID: $0.playerId)
            }
            let intents = try? await intentsTask
            let nextIntentByPlayerID = Dictionary(uniqueKeysWithValues: (intents?.items ?? []).map { ($0.playerId, $0.intent) })
            trainingIntentByPlayerID = nextIntentByPlayerID
            errorMessage = nil
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func setCancelled(_ cancelled: Bool) async {
        isUpdatingStatus = true
        defer { isUpdatingStatus = false }

        do {
            training = try await api.updateTraining(id: training.id, status: cancelled ? "CANCELLED" : "PLANNED")
            errorMessage = nil
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func updateTrainingSchedule(startDate: Date, endTime: String?) async {
        isUpdatingStatus = true
        defer { isUpdatingStatus = false }

        do {
            training = try await api.updateTraining(
                id: training.id,
                dateISO8601: DateFormatters.isoString(from: startDate),
                endTime: endTime
            )
            errorMessage = nil
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func deleteTraining() async -> Bool {
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await api.deleteTraining(id: training.id)
            errorMessage = nil
            return true
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
            return false
        }
    }

    func savePresentPlayerIDs(_ selectedPlayerIDs: Set<String>, availablePlayers: [Player]) async -> String? {
        let previousAttendance = attendance
        let payloadPlayerIDs = Array(selectedPlayerIDs).sorted()

        isSavingAttendance = true
        defer { isSavingAttendance = false }
        attendance = mergedAttendance(from: previousAttendance, selectedPlayerIDs: selectedPlayerIDs, availablePlayers: players)

        do {
            _ = try await api.updateTrainingAttendance(
                trainingID: training.id,
                playerIDs: payloadPlayerIDs
            )
            let refreshedAttendance = try await api.allAttendanceBySession(type: "TRAINING", sessionID: training.id)
            attendance = mergedAttendance(from: refreshedAttendance, selectedPlayerIDs: selectedPlayerIDs, availablePlayers: players)
            errorMessage = nil
            return nil
        } catch {
            attendance = previousAttendance
            if !error.isCancellationError { errorMessage = error.localizedDescription }
            return error.localizedDescription
        }
    }

    func addDrill(drillID: String) async -> Bool {
        guard !trainingDrills.contains(where: { $0.drillId == drillID }) else { return true }
        isSavingDrills = true
        defer { isSavingDrills = false }

        do {
            let newDrill = try await api.addTrainingDrill(trainingID: training.id, drillID: drillID)
            trainingDrills = (trainingDrills + [newDrill]).sorted { lhs, rhs in
                lhs.order < rhs.order || (lhs.order == rhs.order && lhs.id < rhs.id)
            }
            errorMessage = nil
            return true
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
            return false
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
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }

        isSavingDrills = false
    }

    func moveDrills(from sourceOffsets: IndexSet, to destination: Int) async {
        let previous = trainingDrills
        var reordered = trainingDrills
        reordered.move(fromOffsets: sourceOffsets, toOffset: destination)
        guard reordered.map(\.id) != previous.map(\.id) else { return }
        reordered = reordered.enumerated().map { index, item in
            TrainingDrill(id: item.id, trainingId: item.trainingId, drillId: item.drillId, order: index)
        }
        trainingDrills = reordered
        isSavingDrills = true

        do {
            let previousOrderByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.order) })
            let changed = reordered.filter { item in
                previousOrderByID[item.id] != item.order
            }
            for item in changed {
                _ = try await api.updateTrainingDrillOrder(trainingID: training.id, trainingDrillID: item.id, order: item.order)
            }
            let reloaded = try await api.trainingDrills(trainingID: training.id).sorted { lhs, rhs in
                lhs.order < rhs.order || (lhs.order == rhs.order && lhs.id < rhs.id)
            }
            trainingDrills = reloaded
            errorMessage = nil
        } catch {
            trainingDrills = previous
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }

        isSavingDrills = false
    }

    func moveDrill(trainingDrillID: String, before destinationTrainingDrillID: String) async {
        guard let currentIndex = trainingDrills.firstIndex(where: { $0.id == trainingDrillID }) else { return }
        guard let destinationIndex = trainingDrills.firstIndex(where: { $0.id == destinationTrainingDrillID }) else { return }
        guard currentIndex != destinationIndex else { return }

        let targetIndex = currentIndex < destinationIndex ? destinationIndex + 1 : destinationIndex
        await moveDrills(from: IndexSet(integer: currentIndex), to: targetIndex)
    }

    func saveRoleEntries(_ entries: [TrainingRoleEntry]) async -> Bool {
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
            return true
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
            return false
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
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: TrainingDetailViewModel
    @State private var isAttendanceSheetPresented = false
    @State private var attendanceDraftPlayerIDs: Set<String> = []
    @State private var isExercisesSheetPresented = false
    @State private var selectedDrillID: String?
    @State private var pendingDrillIDToAdd: String?
    @State private var roleEditor: RoleEditorState?
    @State private var pendingRoleSaveRequest: PendingRoleSaveRequest?
    @State private var isDeleteConfirmationPresented = false
    @State private var bannerMessage: String?
    @State private var bannerToken = UUID()
    @State private var trainingTimeDraft = Date()
    @State private var trainingEndTimeDraft = ""
    @State private var trainingEndTimePicker = Date()

    init(training: Training) {
        _viewModel = StateObject(wrappedValue: TrainingDetailViewModel(training: training))
    }

    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 20) {
                Text(DateFormatters.displayDateOnly(viewModel.training.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, -8)

                if isCancelled {
                    TrainingStatusBanner(
                        title: "Entraînement annulé",
                        message: "Cette séance est actuellement marquée comme annulée."
                    )
                }

                PlayersAttendanceCard(
                    players: filteredPlayers,
                    presentPlayerIDs: presentPlayerIDs,
                    writable: writable,
                    isSaving: viewModel.isSavingAttendance
                ) {
                    attendanceDraftPlayerIDs = presentPlayerIDs
                    isAttendanceSheetPresented = true
                }

                TrainingInfoCard(
                    training: viewModel.training,
                    writable: writable && !isCancelled,
                    isSaving: viewModel.isUpdatingStatus,
                    draftStartTime: $trainingTimeDraft,
                    draftEndTime: $trainingEndTimeDraft,
                    endTimePicker: $trainingEndTimePicker
                ) {
                    Task {
                        let normalizedEndTime = trainingEndTimeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        await viewModel.updateTrainingSchedule(
                            startDate: trainingTimeDraft,
                            endTime: normalizedEndTime.isEmpty ? nil : normalizedEndTime
                        )
                    }
                }

                ExercisesCard(
                    trainingDrills: viewModel.trainingDrills,
                    drillByID: drillByID,
                    writable: writable,
                    isSaving: viewModel.isSavingDrills,
                    onManage: {
                        isExercisesSheetPresented = true
                    },
                    onMove: { sourceOffsets, destination in
                        Task {
                            await viewModel.moveDrills(from: sourceOffsets, to: destination)
                        }
                    },
                    onRemove: { trainingDrillIDs in
                        Task {
                            for trainingDrillID in trainingDrillIDs {
                                await viewModel.removeDrill(trainingDrillID: trainingDrillID)
                            }
                        }
                    },
                    onOpen: { drillID in
                        selectedDrillID = drillID
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
                            _ = await viewModel.saveRoleEntries(viewModel.roleEntries.filter { $0.id != roleID })
                        }
                    }
                )
            }
            .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .top) {
            if let bannerMessage {
                ErrorBanner(message: bannerMessage) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.bannerMessage = nil
                    }
                    viewModel.errorMessage = nil
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationTitle("Entraînement")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if viewModel.isLoading {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if writable {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(viewModel.training.status == "CANCELLED" ? "Réactiver" : "Annuler") {
                            Task {
                                await viewModel.setCancelled(viewModel.training.status != "CANCELLED")
                            }
                        }
                        .disabled(viewModel.isUpdatingStatus || viewModel.isDeleting)

                        Button("Supprimer", role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                        .disabled(viewModel.isDeleting || viewModel.isUpdatingStatus)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            await viewModel.load()
            if let parsed = DateFormatters.parseISODate(viewModel.training.date) {
                trainingTimeDraft = parsed
            }
            trainingEndTimeDraft = viewModel.training.endTime ?? ""
            if let parsedEndTime = Self.dateFromHHmm(trainingEndTimeDraft, on: trainingTimeDraft) {
                trainingEndTimePicker = parsedEndTime
            }
        }
        .onChange(of: viewModel.training.date) { _, newValue in
            if let parsed = DateFormatters.parseISODate(newValue) {
                trainingTimeDraft = parsed
                if let parsedEndTime = Self.dateFromHHmm(trainingEndTimeDraft, on: parsed) {
                    trainingEndTimePicker = parsedEndTime
                }
            }
        }
        .onChange(of: viewModel.training.endTime) { _, newValue in
            trainingEndTimeDraft = newValue ?? ""
            if let parsedEndTime = Self.dateFromHHmm(trainingEndTimeDraft, on: trainingTimeDraft) {
                trainingEndTimePicker = parsedEndTime
            }
        }
        .refreshable {
            await viewModel.load()
        }
        .sheet(isPresented: $isAttendanceSheetPresented) {
            AttendanceSelectionSheet(
                players: filteredPlayers,
                trainingIntentByPlayerID: viewModel.trainingIntentByPlayerID,
                selectedPlayerIDs: $attendanceDraftPlayerIDs,
                isSaving: viewModel.isSavingAttendance
            ) {
                await viewModel.savePresentPlayerIDs(attendanceDraftPlayerIDs, availablePlayers: filteredPlayers)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $isExercisesSheetPresented) {
            DrillSelectionSheet(
                drills: selectableDrills,
                selectedDrillIDs: Set(viewModel.trainingDrills.map(\.drillId)),
                isSaving: viewModel.isSavingDrills
            ) { drillID in
                pendingDrillIDToAdd = drillID
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
                pendingRoleSaveRequest = PendingRoleSaveRequest(editor: editor, entry: updatedEntry)
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Supprimer cet entraînement ?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                Task {
                    let deleted = await viewModel.deleteTraining()
                    if deleted {
                        dismiss()
                    }
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette action est définitive.")
        }
        .task(id: pendingDrillIDToAdd) {
            guard let pendingDrillIDToAdd else { return }
            let didAdd = await viewModel.addDrill(drillID: pendingDrillIDToAdd)
            if didAdd {
                isExercisesSheetPresented = false
            }
            self.pendingDrillIDToAdd = nil
        }
        .task(id: pendingRoleSaveRequest?.id) {
            guard let pendingRoleSaveRequest else { return }
            var nextRoles = viewModel.roleEntries
            if pendingRoleSaveRequest.editor.mode == .edit {
                if let index = nextRoles.firstIndex(where: { $0.id == pendingRoleSaveRequest.entry.id }) {
                    nextRoles[index] = pendingRoleSaveRequest.entry
                }
            } else {
                nextRoles.append(pendingRoleSaveRequest.entry)
            }

            let didSave = await viewModel.saveRoleEntries(nextRoles)
            if didSave {
                roleEditor = nil
            }
            self.pendingRoleSaveRequest = nil
        }
        .navigationDestination(item: $selectedDrillID) { drillID in
            DrillDetailView(drillID: drillID)
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            let token = UUID()
            bannerToken = token
            withAnimation(.easeInOut(duration: 0.2)) {
                bannerMessage = newValue
            }

            Task {
                try? await Task.sleep(for: .seconds(4))
                guard bannerToken == token else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        bannerMessage = nil
                    }
                }
            }
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

    private var isCancelled: Bool {
        viewModel.training.status?.uppercased() == "CANCELLED"
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

    fileprivate static func dateFromHHmm(_ value: String, on baseDate: Date) -> Date? {
        let parts = value.split(separator: ":")
        guard parts.count == 2 else { return nil }
        guard let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        guard (0 ... 23).contains(hour), (0 ... 59).contains(minute) else { return nil }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)
    }

    fileprivate static func hhmm(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }
}

private struct PlayersAttendanceCard: View {
    let players: [Player]
    let presentPlayerIDs: Set<String>
    let writable: Bool
    let isSaving: Bool
    let onManage: () -> Void

    var body: some View {
        DetailCard {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(spacing: 8) {
                    SectionHeaderLabel(title: "Joueurs", systemImage: "person.2")
                    Text("\(presentPlayers.count)/\(players.count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if writable {
                    Button("Ajouter") {
                        onManage()
                    }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSaving)
                }
            }

            if presentPlayers.isEmpty {
                Text("Aucun joueur pour le moment")
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
        }
    }

    private var presentPlayers: [Player] {
        players.filter { presentPlayerIDs.contains($0.id) }
    }

    private func displayName(for player: Player) -> String {
        player.firstName ?? player.name
    }
}

private struct TrainingInfoCard: View {
    let training: Training
    let writable: Bool
    let isSaving: Bool
    @Binding var draftStartTime: Date
    @Binding var draftEndTime: String
    @Binding var endTimePicker: Date
    let onSave: () -> Void

    var body: some View {
        DetailCard {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SectionHeaderLabel(title: "Informations", systemImage: "info.circle")
                Spacer()
            }

            if writable {
                VStack(alignment: .leading, spacing: 10) {
                    DatePicker(
                        "Horaire",
                        selection: $draftStartTime,
                        displayedComponents: [.hourAndMinute]
                    )
                    .datePickerStyle(.compact)

                    DatePicker(
                        "Heure de fin",
                        selection: Binding(
                            get: { endTimePicker },
                            set: { newValue in
                                endTimePicker = newValue
                                draftEndTime = TrainingDetailView.hhmm(from: newValue)
                            }
                        ),
                        displayedComponents: [.hourAndMinute]
                    )
                    .datePickerStyle(.compact)

                    HStack(spacing: 10) {
                        Button("Effacer la fin") {
                            draftEndTime = ""
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSaving || draftEndTime.isEmpty)

                        Button("Enregistrer") {
                            onSave()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                    }
                }
            } else {
                Text("Horaire: \(trainingTimeLabel(training.date, endTime: training.endTime) ?? "—")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func trainingTimeLabel(_ isoDate: String, endTime: String?) -> String? {
        guard let date = DateFormatters.parseISODate(isoDate) else { return nil }
        let start = date.formatted(date: .omitted, time: .shortened)
        if let endTime, !endTime.isEmpty {
            return "\(start) - \(endTime)"
        }
        return start
    }
}

private struct ExercisesCard: View {
    let trainingDrills: [TrainingDrill]
    let drillByID: [String: Drill]
    let writable: Bool
    let isSaving: Bool
    let onManage: () -> Void
    let onMove: (IndexSet, Int) -> Void
    let onRemove: ([String]) -> Void
    let onOpen: (String) -> Void

    var body: some View {
        DetailCard {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SectionHeaderLabel(title: "Exercices", systemImage: "figure.run")
                Spacer()

                if writable {
                    Button("Modifier") {
                        onManage()
                    }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSaving)
                }
            }

            if trainingDrills.isEmpty {
                Text("Aucun exercice associé à cette séance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(trainingDrills) { item in
                        let drill = drillByID[item.drillId]
                        Button {
                            onOpen(item.drillId)
                        } label: {
                            HStack(spacing: 12) {
                                Text(drill?.title ?? "Exercice")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)

                                Spacer()

                                if writable {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemBackground))
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onMove(perform: writable && !isSaving ? onMove : nil)
                    .onDelete { indexSet in
                        guard writable, !isSaving else { return }
                        let ids = indexSet.map { trainingDrills[$0].id }
                        onRemove(ids)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .scrollDisabled(true)
                .scrollClipDisabled()
                .contentMargins(.vertical, 0, for: .scrollContent)
                .frame(height: min(CGFloat(trainingDrills.count) * 52, 360))
            }
        }
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
        DetailCard {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SectionHeaderLabel(title: "Rôles", systemImage: "person.crop.circle.badge.checkmark")
                Spacer()

                if writable {
                    Button("Ajouter") {
                        onAdd()
                    }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSaving)
                }
            }

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
        }
    }
}

private struct SectionHeaderLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
                        .font(.headline)
        } icon: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AttendanceSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let players: [Player]
    let trainingIntentByPlayerID: [String: String]
    @Binding var selectedPlayerIDs: Set<String>
    let isSaving: Bool
    let onSave: () async -> String?

    @State private var sheetErrorMessage: String?
    @State private var isSubmitting = false
    @State private var searchText = ""

    init(
        players: [Player],
        trainingIntentByPlayerID: [String: String],
        selectedPlayerIDs: Binding<Set<String>>,
        isSaving: Bool,
        onSave: @escaping () async -> String?
    ) {
        self.players = players
        self.trainingIntentByPlayerID = trainingIntentByPlayerID
        self._selectedPlayerIDs = selectedPlayerIDs
        self.isSaving = isSaving
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                if let sheetErrorMessage {
                    Section {
                        Text(sheetErrorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }

                Section("Joueurs") {
                    ForEach(filteredPlayers) { player in
                        Button {
                            toggle(player.id)
                        } label: {
                            HStack(spacing: 12) {
                                PlayerAvatar(player: player, size: 42)
                                Text(player.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                intentBadge(for: trainingIntentByPlayerID[player.id] ?? "UNKNOWN")
                                Image(systemName: selectedPlayerIDs.contains(player.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedPlayerIDs.contains(player.id) ? Color.green : Color.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving || isSubmitting)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Rechercher un joueur")
            .navigationTitle("Joueurs présents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(isSaving || isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submit()
                    } label: {
                        if isSaving || isSubmitting {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                        }
                    }
                    .disabled(isSaving || isSubmitting)
                }
            }
        }
    }

    private var filteredPlayers: [Player] {
        guard !searchText.isEmpty else { return players }
        let needle = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return players.filter { player in
            player.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle)
        }
    }

    private func toggle(_ playerID: String) {
        sheetErrorMessage = nil
        if selectedPlayerIDs.contains(playerID) {
            selectedPlayerIDs.remove(playerID)
        } else {
            selectedPlayerIDs.insert(playerID)
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        sheetErrorMessage = nil
        Task {
            isSubmitting = true
            defer { isSubmitting = false }
            if let errorMessage = await onSave() {
                sheetErrorMessage = errorMessage
            } else {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func intentBadge(for intent: String) -> some View {
        let normalized = intent.uppercased()
        if normalized == "PRESENT" {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Intention: présent")
        } else if normalized == "ABSENT" {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Intention: absent")
        } else {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Intention: inconnue")
        }
    }
}

private struct DrillSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let drills: [Drill]
    let selectedDrillIDs: Set<String>
    let isSaving: Bool
    let onAdd: (String) -> Void

    @State private var query = ""

    init(
        drills: [Drill],
        selectedDrillIDs: Set<String>,
        isSaving: Bool,
        onAdd: @escaping (String) -> Void
    ) {
        self.drills = drills
        self.selectedDrillIDs = selectedDrillIDs
        self.isSaving = isSaving
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            List(filteredDrills) { drill in
                NavigationLink(value: drill.id) {
                    drillRow(for: drill)
                }
                .disabled(isSaving || selectedDrillIDs.contains(drill.id))
            }
            .searchable(text: $query, prompt: "Rechercher un exercice")
            .navigationTitle("Choisissez un exercice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
            .navigationDestination(for: String.self) { drillID in
                DrillLibraryDetailView(
                    drillID: drillID,
                    canAdd: !selectedDrillIDs.contains(drillID),
                    isSaving: isSaving
                ) {
                    onAdd(drillID)
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

    @ViewBuilder
    private func drillRow(for drill: Drill) -> some View {
        let subtitle = [drill.category, "\(drill.duration) min", drill.players].joined(separator: " • ")
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(drill.title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selectedDrillIDs.contains(drill.id) {
                Text("Déjà sélectionné")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.14), in: Capsule())
            }
        }
    }
}

private struct DrillLibraryDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let drillID: String
    let canAdd: Bool
    let isSaving: Bool
    let onAdd: () -> Void

    var body: some View {
        DrillDetailView(drillID: drillID)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if canAdd {
                        Button {
                            onAdd()
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Ajouter")
                            }
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .onChange(of: isSaving) { oldValue, newValue in
                if oldValue == true, newValue == false {
                    dismiss()
                }
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

private struct PendingRoleSaveRequest: Identifiable {
    let id = UUID()
    let editor: RoleEditorState
    let entry: TrainingRoleEntry
}

private struct RoleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let editor: RoleEditorState
    let availablePlayers: [Player]
    let allPresentPlayers: [Player]
    let playerByID: [String: Player]
    let isSaving: Bool
    let onSave: (TrainingRoleEntry) -> Void

    @State private var role: String
    @State private var playerID: String
    @State private var rollingName = "..."
    @State private var isRandomizing = false
    @State private var isSubmitting = false

    init(
        editor: RoleEditorState,
        availablePlayers: [Player],
        allPresentPlayers: [Player],
        playerByID: [String: Player],
        isSaving: Bool,
        onSave: @escaping (TrainingRoleEntry) -> Void
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
                            Text("Tirage au sort")
                        }
                    }
                    .disabled(candidatePlayers.isEmpty || isSaving || isSubmitting)
                }
            }
            .navigationTitle(editor.mode == .add ? "Ajouter un rôle" : "Modifier le rôle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(isSaving || isSubmitting || isRandomizing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isSubmitting = true
                        onSave(TrainingRoleEntry(id: editor.entry.id, role: role, playerID: playerID))
                    } label: {
                        if isSaving || isSubmitting {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                        }
                    }
                    .disabled(playerID.isEmpty || isSaving || isSubmitting || isRandomizing)
                }
            }
            .onChange(of: isSaving) { oldValue, newValue in
                if oldValue == true, newValue == false {
                    isSubmitting = false
                }
            }
            .fullScreenCover(isPresented: $isRandomizing) {
                RandomizingOverlay(name: rollingName)
                    .presentationBackground(.clear)
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
            for _ in 0 ..< 25 {
                if let random = candidatePlayers.randomElement() {
                    rollingName = random.name
                    playerID = random.id
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            try? await Task.sleep(for: .seconds(1))
            isRandomizing = false
        }
    }
}

private struct RandomizingOverlay: View {
    let name: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            Text(firstName)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .padding(.horizontal, 24)
        }
    }

    private var firstName: String {
        let parts = name.split(separator: " ")
        return parts.first.map(String.init) ?? name
    }
}

private struct PlayerAvatar: View {
    let player: Player?
    let size: CGFloat

    private static let palette: [Color] = [
        .red,
        .orange,
        .yellow,
        .green,
        .mint,
        .teal,
        .cyan,
        .blue,
        .indigo,
        .pink
    ]

    var body: some View {
        Circle()
            .fill(backgroundColor.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }

    private var initials: String {
        let source = player?.name ?? "?"
        let parts = source.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private var backgroundColor: Color {
        let source = player?.id ?? player?.name ?? "?"
        let index = abs(source.hashValue) % Self.palette.count
        return Self.palette[index]
    }
}

private struct ErrorBanner: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.red, Color.red.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
    }
}

private struct TrainingStatusBanner: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct DetailCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: shape)
        .overlay {
            shape
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.06)
                        : Color.black.opacity(0.08),
                    lineWidth: 1
                )
        }
        .shadow(
            color: colorScheme == .dark ? .clear : Color.black.opacity(0.06),
            radius: 10,
            y: 3
        )
    }
}
