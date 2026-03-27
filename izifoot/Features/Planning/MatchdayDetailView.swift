import Combine
import CoreLocation
import CoreImage.CIFilterBuiltins
import MapKit
import SwiftUI
import UIKit

fileprivate enum MatchdayMatchMode: String, CaseIterable, Identifiable {
    case manual = "Manuel"
    case rotation = "Rotation"

    var id: String { rawValue }
}

fileprivate struct ManualMatchDraft: Equatable {
    var opponentName = ""
    var played = false
    var homeScore = 0
    var awayScore = 0
    var scorerIDs: [String] = []
}

fileprivate struct ManualMatchEditorState: Identifiable {
    let id = UUID()
    let match: MatchLite?
}

fileprivate struct MatchNavigationDestination: Identifiable, Hashable {
    let id: String
}

fileprivate enum MatchdayModeSwitchConfirmation: Identifiable {
    case manualToRotation
    case rotationToManual

    var id: String {
        switch self {
        case .manualToRotation: return "manualToRotation"
        case .rotationToManual: return "rotationToManual"
        }
    }
}

@MainActor
final class MatchdayDetailViewModel: ObservableObject {
    @Published private(set) var matchday: Matchday
    @Published private(set) var clubName: String?
    @Published private(set) var players: [Player] = []
    @Published private(set) var attendance: [AttendanceRow] = []
    @Published private(set) var matches: [MatchLite] = []
    @Published private(set) var summary: MatchdaySummary?
    @Published private(set) var planning: Planning?
    @Published private(set) var publicShareURL: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isUpdatingAttendance = false
    @Published private(set) var isUpdatingMatches = false
    @Published private(set) var isSavingInfo = false
    @Published private(set) var isSharing = false
    @Published private(set) var isDeletingMatchday = false
    @Published private(set) var planningSaveRevision = 0
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(matchday: Matchday, api: IzifootAPI? = nil) {
        self.matchday = matchday
        self.api = api ?? IzifootAPI()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let clubTask = api.myClub()
            async let playersTask = api.allPlayers()
            async let attendanceTask = api.allAttendanceBySession(type: "PLATEAU", sessionID: matchday.id)
            async let matchesTask = api.allMatches(matchdayID: matchday.id)
            async let summaryTask = api.matchdaySummary(id: matchday.id)
            async let planningsTask = api.plannings()

            let club = try? await clubTask
            clubName = club?.name
            players = try await playersTask.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            attendance = try await attendanceTask
            let plannings = (try? await planningsTask) ?? []
            let fallbackMatches = try await matchesTask
            let summaryValue = try? await summaryTask
            summary = summaryValue
            planning = plannings.first(where: { planning in
                planning.date.prefix(10) == matchday.date.prefix(10)
            })
            matches = {
                guard let summaryMatches = summaryValue?.matches, !summaryMatches.isEmpty else {
                    return fallbackMatches
                }
                return summaryMatches
            }()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAttendance(playerID: String, present: Bool) async {
        let previous = attendance
        isUpdatingAttendance = true

        if let index = attendance.firstIndex(where: { $0.playerId == playerID }) {
            let current = attendance[index]
            attendance[index] = AttendanceRow(
                id: current.id,
                sessionType: current.sessionType,
                sessionId: current.sessionId,
                playerId: current.playerId,
                present: present
            )
        } else {
            attendance.append(
                AttendanceRow(
                    id: nil,
                    sessionType: "PLATEAU",
                    sessionId: matchday.id,
                    playerId: playerID,
                    present: present
                )
            )
        }

        do {
            try await api.setAttendance(sessionType: "PLATEAU", sessionID: matchday.id, playerID: playerID, present: present)
            errorMessage = nil
        } catch {
            attendance = previous
            errorMessage = error.localizedDescription
        }

        isUpdatingAttendance = false
    }

    func savePresentPlayerIDs(_ selectedPlayerIDs: Set<String>, availablePlayers: [Player]) async -> String? {
        let previousAttendance = attendance
        let availablePlayerIDs = Set(availablePlayers.map(\.id))
        let previousByPlayerID = Dictionary(uniqueKeysWithValues: previousAttendance.map { ($0.playerId, $0.present) })

        isUpdatingAttendance = true
        defer { isUpdatingAttendance = false }

        attendance = mergedAttendance(from: previousAttendance, selectedPlayerIDs: selectedPlayerIDs, availablePlayers: availablePlayers)

        do {
            for playerID in availablePlayerIDs {
                let previousValue = previousByPlayerID[playerID] ?? false
                let nextValue = selectedPlayerIDs.contains(playerID)
                guard previousValue != nextValue else { continue }
                try await api.setAttendance(sessionType: "PLATEAU", sessionID: matchday.id, playerID: playerID, present: nextValue)
            }
            let refreshedAttendance = try await api.allAttendanceBySession(type: "PLATEAU", sessionID: matchday.id)
            attendance = mergedAttendance(from: refreshedAttendance, selectedPlayerIDs: selectedPlayerIDs, availablePlayers: availablePlayers)
            errorMessage = nil
            return nil
        } catch {
            attendance = previousAttendance
            errorMessage = error.localizedDescription
            return error.localizedDescription
        }
    }

    func saveInfo(address: String, startTime: String, meetingTime: String) async -> Bool {
        isSavingInfo = true
        defer { isSavingInfo = false }

        do {
            matchday = try await api.updateMatchday(
                id: matchday.id,
                address: address.isEmpty ? nil : address,
                startTime: startTime.isEmpty ? nil : startTime,
                meetingTime: meetingTime.isEmpty ? nil : meetingTime
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func share() async {
        isSharing = true
        defer { isSharing = false }

        do {
            let share = try await api.shareMatchday(id: matchday.id)
            publicShareURL = share.url
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteMatchday() async -> Bool {
        isDeletingMatchday = true
        defer { isDeletingMatchday = false }

        do {
            try await api.deleteMatchday(id: matchday.id)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setRotationTeamAbsence(teamLabel: String, absent: Bool) async {
        isUpdatingMatches = true
        defer { isUpdatingMatches = false }

        do {
            try await api.setMatchdayTeamAbsence(id: matchday.id, teamLabel: teamLabel, absent: absent)
            await reloadMatchesState()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    fileprivate func saveManualMatch(draft: ManualMatchDraft, matchID: String?) async -> Bool {
        let opponentName = draft.opponentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !opponentName.isEmpty else {
            errorMessage = "Le nom de l'adversaire est obligatoire."
            return false
        }

        isUpdatingMatches = true
        defer { isUpdatingMatches = false }

        let payload = MatchPayload(
            type: "PLATEAU",
            matchdayId: matchday.id,
            sides: .empty,
            score: MatchScorePayload(
                home: draft.played ? draft.homeScore : 0,
                away: draft.played ? draft.awayScore : 0
            ),
            buteurs: draft.played ? draft.scorerIDs.map { MatchScorerPayload(playerId: $0, side: "home") } : [],
            opponentName: opponentName,
            played: draft.played,
            rotationGameKey: nil,
            tactic: nil
        )

        do {
            if let matchID {
                _ = try await api.updateMatch(id: matchID, payload: payload)
            } else {
                _ = try await api.createMatch(payload: payload)
            }
            await reloadMatchesState()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteMatch(id: String) async {
        isUpdatingMatches = true
        defer { isUpdatingMatches = false }

        do {
            try await api.deleteMatch(id: id)
            await reloadMatchesState()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func savePlanning(data: PlanningData) async -> Bool {
        isUpdatingMatches = true
        defer { isUpdatingMatches = false }

        do {
            let savedPlanning: Planning
            if let planning {
                savedPlanning = try await api.updatePlanning(id: planning.id, data: data)
            } else {
                savedPlanning = try await api.createPlanning(dateISO: matchday.date, data: data)
            }
            self.planning = savedPlanning

            do {
                try await regenerateMatchesFromPlanning(data: data)
            } catch {
                errorMessage = error.localizedDescription
            }

            await reloadMatchesState()
            planningSaveRevision += 1
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deletePlanningAndRotationMatches() async -> Bool {
        isUpdatingMatches = true
        defer { isUpdatingMatches = false }

        do {
            if let planning {
                try await api.deletePlanning(id: planning.id)
                self.planning = nil
            }
            for match in matches where normalizedRotationKey(for: match) != nil {
                try await api.deleteMatch(id: match.id)
            }
            await reloadMatchesState()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func regenerateMatchesFromPlanning(data: PlanningData) async throws {
        for match in matches {
            try await api.deleteMatch(id: match.id)
        }

        let clubTeamLabels = resolveClubTeamLabels(in: data)

        for (slotIndex, slot) in data.slots.enumerated() {
            for (gameIndex, game) in slot.games.enumerated() where clubTeamLabels.contains(game.a) || clubTeamLabels.contains(game.b) {
                let opponent = clubTeamLabels.contains(game.a) ? game.b : game.a
                let payload = MatchPayload(
                    type: "PLATEAU",
                    matchdayId: matchday.id,
                    sides: .empty,
                    score: MatchScorePayload(home: 0, away: 0),
                    buteurs: [],
                    opponentName: opponent,
                    played: false,
                    rotationGameKey: "slot:\(slotIndex):game:\(gameIndex)",
                    tactic: nil
                )
                _ = try await api.createMatch(payload: payload)
            }
        }
    }

    private func resolveClubTeamLabels(in planningData: PlanningData) -> Set<String> {
        let normalizedClubName = clubName?.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) ?? ""
        let labels = planningData.teams
            .map(\.label)
            .filter { label in
                let normalizedLabel = label.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                return !normalizedClubName.isEmpty && normalizedLabel.contains(normalizedClubName)
            }
        if labels.isEmpty, let first = planningData.teams.first?.label {
            return [first]
        }
        return Set(labels)
    }

    private func reloadMatchesState() async {
        let refreshedSummary = try? await api.matchdaySummary(id: matchday.id)
        summary = refreshedSummary
        let refreshedPlannings = (try? await api.plannings()) ?? []
        planning = refreshedPlannings.first(where: { planning in
            planning.date.prefix(10) == matchday.date.prefix(10)
        })
        if let summaryMatches = refreshedSummary?.matches, !summaryMatches.isEmpty {
            matches = summaryMatches
        } else if let refreshedMatches = try? await api.allMatches(matchdayID: matchday.id) {
            matches = refreshedMatches
        }
    }

    private func normalizedRotationKey(for match: MatchLite) -> String? {
        guard let key = match.rotationGameKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }
        return key
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
                    sessionType: "PLATEAU",
                    sessionId: matchday.id,
                    playerId: playerID,
                    present: selectedPlayerIDs.contains(playerID)
                )
            }
        }

        return rowsByPlayerID.values.sorted { lhs, rhs in lhs.playerId < rhs.playerId }
    }
}

struct MatchdayDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var teamScopeStore: TeamScopeStore

    @StateObject private var viewModel: MatchdayDetailViewModel
    @State private var isAttendanceSheetPresented = false
    @State private var attendanceDraftPlayerIDs: Set<String> = []
    @State private var isEditSchedulePresented = false
    @State private var pendingScheduleSaveRequest: PendingScheduleSaveRequest?
    @State private var manualMatchEditor: ManualMatchEditorState?
    @State private var isPlanningDetailPresented = false
    @State private var isShareSheetPresented = false
    @State private var selectedMatchDestination: MatchNavigationDestination?
    @State private var isDeleteMatchdayConfirmationPresented = false

    init(matchday: Matchday) {
        _viewModel = StateObject(wrappedValue: MatchdayDetailViewModel(matchday: matchday))
    }

    var body: some View {
        MatchdayDetailScaffold(
            viewModel: viewModel,
            filteredPlayers: filteredPlayers,
            presentPlayerIDs: presentPlayerIDs,
            writable: writable,
            isEditSchedulePresented: $isEditSchedulePresented,
            pendingScheduleSaveRequest: $pendingScheduleSaveRequest,
            isAttendanceSheetPresented: $isAttendanceSheetPresented,
            attendanceDraftPlayerIDs: $attendanceDraftPlayerIDs,
            manualMatchEditor: $manualMatchEditor,
            pageContent: AnyView(pageContent),
            onSaveSchedule: { request in
                let didSave = await viewModel.saveInfo(
                    address: request.address,
                    startTime: request.startTime,
                    meetingTime: request.meetingTime
                )
                return didSave
            },
            onSaveAttendance: {
                await viewModel.savePresentPlayerIDs(attendanceDraftPlayerIDs, availablePlayers: filteredPlayers)
            },
            manualDraft: { match in
                manualDraft(from: match)
            },
            onSaveManualMatch: { editor, draft in
                await viewModel.saveManualMatch(draft: draft, matchID: editor.match?.id)
            },
            onDeleteManualMatch: { editor in
                guard let match = editor.match else { return false }
                await viewModel.deleteMatch(id: match.id)
                return true
            },
            onSavePlanning: { planningData in
                await viewModel.savePlanning(data: planningData)
            },
            onAppear: {}
        )
        .toolbar {
            if writable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isDeleteMatchdayConfirmationPresented = true
                    } label: {
                        if viewModel.isDeletingMatchday {
                            ProgressView()
                        } else {
                            Image(systemName: "trash")
                        }
                    }
                    .disabled(viewModel.isSharing || viewModel.isDeletingMatchday)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        if viewModel.publicShareURL == nil {
                            await viewModel.share()
                        }
                        if viewModel.publicShareURL != nil {
                            isShareSheetPresented = true
                        }
                    }
                } label: {
                    if viewModel.isSharing {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(viewModel.isSharing || viewModel.isDeletingMatchday)
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            if let publicShareURL = viewModel.publicShareURL {
                MatchdayShareSheet(urlString: publicShareURL)
            }
        }
        .confirmationDialog(
            "Supprimer le plateau ?",
            isPresented: $isDeleteMatchdayConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                Task {
                    let didDelete = await viewModel.deleteMatchday()
                    if didDelete {
                        dismiss()
                    }
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le plateau, son planning et ses matchs associés seront supprimés.")
        }
        .navigationDestination(isPresented: $isPlanningDetailPresented) {
            MatchdayPlanningDetailView(
                rotation: viewModel.summary?.rotation,
                planning: viewModel.planning,
                clubName: viewModel.clubName,
                writable: writable,
                isSaving: viewModel.isUpdatingMatches,
                planningSaveRevision: viewModel.planningSaveRevision,
                onSave: { planningData in
                    await viewModel.savePlanning(data: planningData)
                },
                onDelete: {
                await viewModel.deletePlanningAndRotationMatches()
                }
            )
        }
        .sheet(item: $selectedMatchDestination) { destination in
            MatchdayMatchesPagerSheet(
                initialMatchID: destination.id,
                matches: orderedMatchesForPager,
                clubName: viewModel.clubName,
                matchdayDate: viewModel.matchday.date,
                playerNamesByID: playerNamesByID,
                matchProvider: { matchID in
                    viewModel.matches.first(where: { $0.id == matchID })
                }
            )
        }
    }

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(DateFormatters.displayDateOnly(viewModel.matchday.date))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            MatchdayInfoCard(
                matchday: viewModel.matchday,
                writable: writable
            ) {
                isEditSchedulePresented = true
            }

            MatchdayPlanningCard {
                isPlanningDetailPresented = true
            }

            MatchdayMatchesCard(
                matches: viewModel.matches,
                rotation: viewModel.summary?.rotation,
                clubName: viewModel.clubName,
                playerNamesByID: playerNamesByID,
                writable: writable,
                onCreateManual: {
                    manualMatchEditor = ManualMatchEditorState(match: nil)
                },
                onEditManual: { match in
                    selectedMatchDestination = MatchNavigationDestination(id: match.id)
                },
                onDeleteMatch: { match in
                    await viewModel.deleteMatch(id: match.id)
                }
            )

            MatchdayPlayersCard(
                players: filteredPlayers,
                presentPlayerIDs: presentPlayerIDs,
                writable: writable,
                isSaving: viewModel.isUpdatingAttendance
            ) {
                attendanceDraftPlayerIDs = presentPlayerIDs
                isAttendanceSheetPresented = true
            }
        }
    }

    private var writable: Bool {
        guard let role = authStore.me?.role else { return false }
        let requiresSelection = (role == .direction || role == .coach) && !teamScopeStore.teams.isEmpty
        return (role == .direction || role == .coach) && (!requiresSelection || teamScopeStore.selectedTeamID != nil)
    }

    private var filteredPlayers: [Player] {
        guard let role = authStore.me?.role, role == .coach else {
            return viewModel.players
        }

        let managed = Set(authStore.me?.managedTeamIds ?? [])
        return viewModel.players.filter { player in
            guard let teamID = player.teamId else { return true }
            return managed.contains(teamID)
        }
    }

    private var attendanceByPlayerID: [String: Bool] {
        Dictionary(uniqueKeysWithValues: viewModel.attendance.map { ($0.playerId, $0.present) })
    }

    private var presentPlayerIDs: Set<String> {
        Set(viewModel.attendance.filter(\.present).map(\.playerId))
    }

    private var playerNamesByID: [String: String] {
        Dictionary(uniqueKeysWithValues: viewModel.players.map { ($0.id, $0.name) })
    }

    private var orderedMatchesForPager: [MatchLite] {
        let planningKeys = Set(
            viewModel.summary?.rotation?.slots.enumerated().flatMap { slotIndex, slot in
                slot.games.enumerated().map { gameIndex, _ in
                    "slot:\(slotIndex):game:\(gameIndex)"
                }
            } ?? []
        )

        let manualMatches = viewModel.matches
            .filter { match in
                guard let key = normalizedRotationKey(for: match) else { return true }
                return !planningKeys.contains(key)
            }
            .sorted(by: sortMatchesForPager)

        let planningMatches = viewModel.matches
            .filter { match in
                guard let key = normalizedRotationKey(for: match) else { return false }
                return planningKeys.contains(key)
            }
            .sorted(by: sortMatchesForPager)

        return manualMatches + planningMatches
    }

    private func sortMatchesForPager(_ lhs: MatchLite, _ rhs: MatchLite) -> Bool {
        let lhsTime = lhs.startTime ?? lhs.createdAt
        let rhsTime = rhs.startTime ?? rhs.createdAt
        if lhsTime == rhsTime { return lhs.id < rhs.id }
        return lhsTime < rhsTime
    }

    private func normalizedRotationKey(for match: MatchLite) -> String? {
        guard let key = match.rotationGameKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }
        return key
    }

    private func manualDraft(from match: MatchLite?) -> ManualMatchDraft {
        guard let match else { return ManualMatchDraft() }
        return ManualMatchDraft(
            opponentName: match.opponentName ?? "",
            played: match.played ?? false,
            homeScore: match.teams.first(where: { $0.side == "home" })?.score ?? 0,
            awayScore: match.teams.first(where: { $0.side == "away" })?.score ?? 0,
            scorerIDs: match.scorers.filter { $0.side == "home" }.map(\.playerId)
        )
    }

}

private struct MatchdayDetailScaffold: View {
    @ObservedObject var viewModel: MatchdayDetailViewModel
    let filteredPlayers: [Player]
    let presentPlayerIDs: Set<String>
    let writable: Bool
    @Binding var isEditSchedulePresented: Bool
    @Binding var pendingScheduleSaveRequest: PendingScheduleSaveRequest?
    @Binding var isAttendanceSheetPresented: Bool
    @Binding var attendanceDraftPlayerIDs: Set<String>
    @Binding var manualMatchEditor: ManualMatchEditorState?
    let pageContent: AnyView
    let onSaveSchedule: (PendingScheduleSaveRequest) async -> Bool
    let onSaveAttendance: () async -> String?
    let manualDraft: (MatchLite?) -> ManualMatchDraft
    let onSaveManualMatch: (ManualMatchEditorState, ManualMatchDraft) async -> Bool
    let onDeleteManualMatch: (ManualMatchEditorState) async -> Bool
    let onSavePlanning: (PlanningData) async -> Bool
    let onAppear: () -> Void

    var body: some View {
        dialogsView
    }

    private var baseListView: some View {
        List {
            pageContent
                .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var loadingView: some View {
        baseListView
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Chargement")
                }
            }
    }

    private var lifecycleView: some View {
        loadingView
            .navigationTitle("Plateau")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
            .task(id: pendingScheduleSaveRequest?.id) {
                guard let pendingScheduleSaveRequest else { return }
                let didSave = await onSaveSchedule(pendingScheduleSaveRequest)
                if didSave {
                    isEditSchedulePresented = false
                }
                self.pendingScheduleSaveRequest = nil
            }
            .onAppear(perform: onAppear)
            .onChange(of: viewModel.summary?.mode) { _, _ in
                onAppear()
            }
    }

    private var sheetsView: some View {
        lifecycleView
            .sheet(isPresented: $isEditSchedulePresented) {
                scheduleSheet
            }
            .sheet(isPresented: $isAttendanceSheetPresented) {
                attendanceSheet
            }
            .sheet(item: $manualMatchEditor) { editor in
                manualMatchSheet(editor)
            }
    }

    private var scheduleSheet: some View {
        EditMatchdayScheduleSheet(matchday: viewModel.matchday, isSaving: viewModel.isSavingInfo) { address, startTime, meetingTime in
            pendingScheduleSaveRequest = PendingScheduleSaveRequest(
                address: address,
                startTime: startTime,
                meetingTime: meetingTime
            )
        }
        .presentationDetents([.medium])
    }

    private var attendanceSheet: some View {
        MatchdayAttendanceSelectionSheet(
            players: filteredPlayers,
            selectedPlayerIDs: $attendanceDraftPlayerIDs,
            isSaving: viewModel.isUpdatingAttendance
        ) {
            await onSaveAttendance()
        }
        .presentationDetents([.large])
    }

    private func manualMatchSheet(_ editor: ManualMatchEditorState) -> AnyView {
        return AnyView(
            ManualMatchEditorSheet(
                draft: manualDraft(editor.match),
                players: filteredPlayers,
                isSaving: viewModel.isUpdatingMatches,
                existingMatch: editor.match,
                onSave: { draft in
                    await onSaveManualMatch(editor, draft)
                }
            )
        )
    }

    private var dialogsView: some View {
        sheetsView
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

private struct MatchdayInfoCard: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case location = "Lieu"
        case schedule = "Horaires"

        var id: String { rawValue }
    }

    let matchday: Matchday
    let writable: Bool
    let onEdit: () -> Void

    @State private var selectedTab: Tab = .location

    var body: some View {
        DetailCard {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Informations")
                    .font(.headline)

                Spacer()

                if writable {
                    Button("Modifier") {
                        onEdit()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Picker("Onglet", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch selectedTab {
            case .location:
                VStack(alignment: .leading, spacing: 12) {
                    AddressMapPreview(address: mapAddress)
                    Text(mapAddress ?? "Adresse à définir")
                        .font(.subheadline)
                        .foregroundStyle(mapAddress == nil ? .secondary : .primary)
                }
            case .schedule:
                VStack(alignment: .leading, spacing: 14) {
                    ScheduleValueRow(
                        title: "Début",
                        value: matchday.startTime ?? "À définir",
                        systemImage: "play.circle"
                    )
                    ScheduleValueRow(
                        title: "Rendez-vous sur le lieu",
                        value: matchday.meetingTime ?? "À définir",
                        systemImage: "figure.walk.arrival"
                    )
                }
            }
        }
    }

    private var mapAddress: String? {
        let trimmedAddress = matchday.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedAddress, !trimmedAddress.isEmpty {
            return trimmedAddress
        }
        let trimmedLocation = matchday.lieu?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedLocation, !trimmedLocation.isEmpty {
            return trimmedLocation
        }
        return nil
    }
}

private struct MatchdayPlanningCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            DetailCard {
                HStack(spacing: 12) {
                    SectionHeaderLabel(title: "Planning", systemImage: "calendar")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MatchdayPlanningDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let rotation: MatchdayRotationSummary?
    let planning: Planning?
    let clubName: String?
    let writable: Bool
    let isSaving: Bool
    let planningSaveRevision: Int
    let onSave: (PlanningData) async -> Bool
    let onDelete: () async -> Bool
    @State private var selectedTeam = "Toutes les équipes"
    @State private var isEditorPresented = false
    @State private var isDeleting = false
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        ScrollView {
            MatchdayPlanningContent(rotation: rotation, selectedTeam: $selectedTeam)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
        }
        .navigationTitle("Planning")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            if writable {
                ToolbarItem(placement: .topBarTrailing) {
                    if hasPlanning {
                        Menu {
                            Button("Modifier") {
                                isEditorPresented = true
                            }

                            Button("Supprimer", role: .destructive) {
                                isDeleteConfirmationPresented = true
                            }
                        } label: {
                            if isDeleting {
                                ProgressView()
                            } else {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                        .disabled(isDeleting)
                    } else {
                        Button("Ajouter") {
                            isEditorPresented = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            PlanningEditorSheet(
                isPresented: $isEditorPresented,
                initialData: planning?.data,
                clubName: clubName,
                isSaving: isSaving,
                onSave: onSave
            )
        }
        .onChange(of: planningSaveRevision) { _, _ in
            isEditorPresented = false
        }
        .confirmationDialog(
            "Supprimer le planning ?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                Task {
                    isDeleting = true
                    let didDelete = await onDelete()
                    isDeleting = false
                    if didDelete {
                        dismiss()
                    }
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le planning et les matchs liés à la rotation seront supprimés.")
        }
    }

    private var hasPlanning: Bool {
        planning != nil
    }
}

private struct MatchdayPlanningContent: View {
    let rotation: MatchdayRotationSummary?
    @Binding var selectedTeam: String

    var body: some View {
        if let rotation, !rotation.slots.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                if teamFilterOptions.count > 1 {
                    Picker("Équipe", selection: $selectedTeam) {
                        ForEach(teamFilterOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if groupedByTime.isEmpty {
                    Text("Aucun créneau pour cette équipe.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groupedByTime) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.time)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(group.gamesByPitch) { pitchGroup in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(formatPitchLabel(pitchGroup.pitchLabel))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)

                                    ForEach(pitchGroup.games) { game in
                                        HStack(spacing: 12) {
                                            MatchTeamPill(
                                                title: game.teamA ?? "Équipe A",
                                                accentColor: color(for: game.teamA),
                                                alignment: .leading
                                            )
                                            Text("vs")
                                                .font(.subheadline.weight(.semibold))
                                                .frame(minWidth: 40)
                                                .foregroundStyle(.secondary)
                                            MatchTeamPill(
                                                title: game.teamB ?? "Équipe B",
                                                accentColor: color(for: game.teamB),
                                                alignment: .trailing
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
            }
        } else {
            Text("Aucun planning enregistré pour ce plateau.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var groupedByTime: [PlanningTimeGroup] {
        guard !filteredSlots.isEmpty else { return [] }

        let grouped = Dictionary(grouping: filteredSlots, by: { $0.time ?? "Horaire à définir" })

        return grouped.keys.sorted().map { time in
            let slots = grouped[time] ?? []
            let games = slots.flatMap(\.games)
            let gamesByPitchDict = Dictionary(grouping: games, by: { game in
                if let pitch = game.pitch, !pitch.isEmpty {
                    return formatPitchLabel(pitch)
                }
                return "Terrain à définir"
            })
            let gamesByPitch = gamesByPitchDict.keys.sorted().map { pitch in
                PlanningPitchGroup(pitchLabel: pitch, games: gamesByPitchDict[pitch] ?? [])
            }
            return PlanningTimeGroup(time: time, gamesByPitch: gamesByPitch)
        }
    }

    private var teamFilterOptions: [String] {
        guard let rotation else { return ["Toutes les équipes"] }
        return ["Toutes les équipes"] + rotation.teams.map(\.label)
    }

    private var filteredSlots: [MatchdayRotationSlot] {
        guard let rotation else { return [] }
        guard selectedTeam != "Toutes les équipes" else { return rotation.slots }
        return rotation.slots.compactMap { slot in
            let games = slot.games.filter { game in
                game.teamA == selectedTeam || game.teamB == selectedTeam
            }
            guard !games.isEmpty else { return nil }
            return MatchdayRotationSlot(id: slot.id, pitch: slot.pitch, time: slot.time, games: games)
        }
    }

    private func color(for teamLabel: String?) -> Color {
        guard
            let teamLabel,
            let team = rotation?.teams.first(where: { $0.label == teamLabel })
        else {
            return .secondary
        }
        return Color(hex: team.color ?? "") ?? .secondary
    }
}

private struct PlanningTimeGroup: Identifiable {
    let id = UUID()
    let time: String
    let gamesByPitch: [PlanningPitchGroup]
}

private struct PlanningPitchGroup: Identifiable {
    let id = UUID()
    let pitchLabel: String
    let games: [MatchdayRotationGame]
}

private struct MatchdayMatchesCard: View {
    let matches: [MatchLite]
    let rotation: MatchdayRotationSummary?
    let clubName: String?
    let playerNamesByID: [String: String]
    let writable: Bool
    let onCreateManual: () -> Void
    let onEditManual: (MatchLite) -> Void
    let onDeleteMatch: (MatchLite) async -> Void

    var body: some View {
        DetailCard {
            HStack(alignment: .center, spacing: 12) {
                SectionHeaderLabel(title: "Matchs", systemImage: "sportscourt")

                Spacer()

                if writable {
                    Button("Ajouter") {
                        onCreateManual()
                    }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            ManualMatchesContent(
                matches: matches,
                rotation: rotation,
                clubName: clubName,
                playerNamesByID: playerNamesByID,
                writable: writable,
                onOpen: onEditManual,
                onDelete: onDeleteMatch
            )
        }
    }
}

private struct ManualMatchesContent: View {
    let matches: [MatchLite]
    let rotation: MatchdayRotationSummary?
    let clubName: String?
    let playerNamesByID: [String: String]
    let writable: Bool
    let onOpen: (MatchLite) -> Void
    let onDelete: (MatchLite) async -> Void

    var body: some View {
        if sortedManualMatches.isEmpty && sortedPlanningMatches.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Aucun match encore enregistré pour ce plateau.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !sortedManualMatches.isEmpty {
                    Text("Matchs ajoutés manuellement")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    ForEach(sortedManualMatches) { match in
                        matchRow(match, allowsDelete: writable)
                    }
                }

                if !sortedPlanningMatches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Matchs issus du planning")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        ForEach(sortedPlanningMatches) { match in
                            matchRow(match, allowsDelete: false)
                        }
                    }
                }
            }
        }
    }

    private var sortedManualMatches: [MatchLite] {
        matches
            .filter { !isPlanningMatch($0) }
            .sorted(by: sortMatches)
    }

    private var sortedPlanningMatches: [MatchLite] {
        matches
            .filter(isPlanningMatch)
            .sorted(by: sortMatches)
    }

    private func sortMatches(_ lhs: MatchLite, _ rhs: MatchLite) -> Bool {
            let lhsTime = lhs.startTime ?? lhs.createdAt
            let rhsTime = rhs.startTime ?? rhs.createdAt
            if lhsTime == rhsTime { return lhs.id < rhs.id }
            return lhsTime < rhsTime
        }

    @ViewBuilder
    private func matchRow(_ match: MatchLite, allowsDelete: Bool) -> some View {
        let planningInfo = planningMatchInfo(for: match)
        Button {
            onOpen(match)
        } label: {
            MatchRowCard(
                titleOverride: planningInfo?.teamA,
                subtitleOverride: planningInfo?.teamB,
                clubName: clubName,
                leftColor: planningInfo?.teamAColor,
                rightColor: planningInfo?.teamBColor,
                match: match,
                playerNamesByID: playerNamesByID,
                showsBackground: false
            )
        }
        .buttonStyle(.plain)
    }

    private func normalizedRotationKey(for match: MatchLite) -> String? {
        guard let key = match.rotationGameKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }
        return key
    }

    private func isPlanningMatch(_ match: MatchLite) -> Bool {
        guard
            let matchKey = normalizedRotationKey(for: match),
            planningKeys.contains(matchKey)
        else {
            return false
        }
        return true
    }

    private var planningKeys: Set<String> {
        Set(
            rotation?.slots.enumerated().flatMap { slotIndex, slot in
                slot.games.enumerated().map { gameIndex, _ in
                    "slot:\(slotIndex):game:\(gameIndex)"
                }
            } ?? []
        )
    }

    private func planningMatchInfo(for match: MatchLite) -> PlanningMatchInfo? {
        guard let key = normalizedRotationKey(for: match) else { return nil }
        return planningMatchesByKey[key]
    }

    private var planningMatchesByKey: [String: PlanningMatchInfo] {
        var result: [String: PlanningMatchInfo] = [:]
        guard let rotation else { return result }

        let colors = Dictionary(uniqueKeysWithValues: rotation.teams.map { ($0.label, Color(hex: $0.color ?? "") ?? .secondary) })

        for (slotIndex, slot) in rotation.slots.enumerated() {
            for (gameIndex, game) in slot.games.enumerated() {
                result["slot:\(slotIndex):game:\(gameIndex)"] = PlanningMatchInfo(
                    teamA: game.teamA,
                    teamB: game.teamB,
                    teamAColor: game.teamA.flatMap { colors[$0] },
                    teamBColor: game.teamB.flatMap { colors[$0] }
                )
            }
        }

        return result
    }
}

private struct PlanningMatchInfo {
    let teamA: String?
    let teamB: String?
    let teamAColor: Color?
    let teamBColor: Color?
}

private struct RotationMatchesContent: View {
    let rotation: MatchdayRotationSummary?
    let planning: Planning?
    let matches: [MatchLite]
    let fallbackMatches: [MatchLite]
    let clubName: String?
    let playerNamesByID: [String: String]
    @Binding var selectedTeam: String
    let writable: Bool
    let isSaving: Bool
    let onCreateOrEditRotation: () -> Void
    let onSetTeamAbsence: (String, Bool) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let updatedAtLabel {
                HStack {
                    Text(updatedAtLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if writable {
                        Button(planning == nil ? "Créer une rotation" : "Modifier") {
                            onCreateOrEditRotation()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            if let rotation, !rotation.teams.isEmpty {
                RotationTeamsAbsenceSection(
                    teams: rotation.teams,
                    writable: writable,
                    isSaving: isSaving,
                    onSetTeamAbsence: onSetTeamAbsence
                )
            }

            if teamFilterOptions.count > 1 {
                Picker("Équipe", selection: $selectedTeam) {
                    ForEach(teamFilterOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            if let rotation, !rotation.slots.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(filteredSlots) { slot in
                        RotationSlotSection(
                            slot: slot,
                            clubName: clubName,
                            teamColorsByLabel: teamColorsByLabel,
                            linkedMatchesByKey: linkedMatchesByKey,
                            playerNamesByID: playerNamesByID
                        )
                    }
                }
            } else if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sortedRotationMatches) { match in
                        MatchRowCard(clubName: clubName, match: match, playerNamesByID: playerNamesByID)
                    }
                }
            } else if !fallbackMatches.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(fallbackMatches) { match in
                        MatchRowCard(clubName: clubName, match: match, playerNamesByID: playerNamesByID)
                    }
                }
            } else {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var updatedAtLabel: String? {
        guard let rawValue = rotation?.updatedAt ?? rotation?.start else { return nil }
        let iso8601 = ISO8601DateFormatter()
        guard let date = iso8601.date(from: rawValue) else { return nil }
        return "Mise à jour le \(date.formatted(date: .numeric, time: .shortened))"
    }

    private var linkedMatchesByKey: [String: MatchLite] {
        Dictionary(uniqueKeysWithValues: matches.compactMap { match in
            guard let key = normalizedRotationKey(for: match) else { return nil }
            return (key, match)
        })
    }

    private var teamColorsByLabel: [String: Color] {
        guard let rotation else { return [:] }
        return Dictionary(uniqueKeysWithValues: rotation.teams.map { ($0.label, Color(hex: $0.color ?? "") ?? .secondary) })
    }

    private var teamFilterOptions: [String] {
        guard let rotation else { return ["Toutes les équipes"] }
        return ["Toutes les équipes"] + rotation.teams.map(\.label)
    }

    private var filteredSlots: [MatchdayRotationSlot] {
        guard let rotation else { return [] }
        guard selectedTeam != "Toutes les équipes" else { return rotation.slots }
        return rotation.slots.compactMap { slot in
            let games = slot.games.filter { game in
                game.teamA == selectedTeam || game.teamB == selectedTeam
            }
            guard !games.isEmpty else { return nil }
            return MatchdayRotationSlot(id: slot.id, pitch: slot.pitch, time: slot.time, games: games)
        }
    }

    private var emptyMessage: String {
        if rotation == nil {
            return fallbackMatches.isEmpty ? "Aucune rotation enregistrée pour ce plateau." : "Aucun match."
        }
        if selectedTeam != "Toutes les équipes" {
            return "Aucun créneau pour cette équipe."
        }
        return "Aucun créneau disponible."
    }

    private var sortedRotationMatches: [MatchLite] {
        matches.sorted { lhs, rhs in
            let lhsTime = lhs.startTime ?? lhs.createdAt
            let rhsTime = rhs.startTime ?? rhs.createdAt
            if lhsTime == rhsTime { return lhs.id < rhs.id }
            return lhsTime < rhsTime
        }
    }

    private func normalizedRotationKey(for match: MatchLite) -> String? {
        guard let key = match.rotationGameKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }
        return key
    }
}

private struct RotationTeamsAbsenceSection: View {
    let teams: [MatchdayRotationTeam]
    let writable: Bool
    let isSaving: Bool
    let onSetTeamAbsence: (String, Bool) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Équipes absentes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(teams) { team in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: team.color) ?? .secondary)
                        .frame(width: 10, height: 10)

                    Text(team.label)
                        .font(.subheadline)

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { team.absent },
                        set: { newValue in
                            Task { await onSetTeamAbsence(team.label, newValue) }
                        }
                    ))
                    .labelsHidden()
                    .disabled(!writable || isSaving)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

private struct RotationSlotSection: View {
    let slot: MatchdayRotationSlot
    let clubName: String?
    let teamColorsByLabel: [String: Color]
    let linkedMatchesByKey: [String: MatchLite]
    let playerNamesByID: [String: String]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(slot.time ?? "Horaire à définir")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(slot.games) { game in
                    RotationGameCard(
                        game: game,
                        clubName: clubName,
                        linkedMatch: linkedMatch(for: game),
                        teamAColor: color(for: game.teamA),
                        teamBColor: color(for: game.teamB),
                        playerNamesByID: playerNamesByID
                    )
                }
            }
        }
    }

    private func linkedMatch(for game: MatchdayRotationGame) -> MatchLite? {
        guard let key = game.key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }
        return linkedMatchesByKey[key]
    }

    private func color(for label: String?) -> Color {
        guard let label else { return .secondary }
        return teamColorsByLabel[label] ?? .secondary
    }
}

private struct RotationGameCard: View {
    let game: MatchdayRotationGame
    let clubName: String?
    let linkedMatch: MatchLite?
    let teamAColor: Color
    let teamBColor: Color
    let playerNamesByID: [String: String]

    var body: some View {
        if let linkedMatch {
            MatchRowCard(
                titleOverride: "\(game.teamA ?? "Équipe A")",
                subtitleOverride: game.teamB ?? "Équipe B",
                timeOverride: game.time ?? linkedMatch.startTime,
                pitchOverride: game.pitch,
                clubName: clubName,
                leftColor: teamAColor,
                rightColor: teamBColor,
                match: linkedMatch,
                playerNamesByID: playerNamesByID
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let pitch = game.pitch, !pitch.isEmpty {
                    Text(formatPitchLabel(pitch))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    MatchTeamPill(title: game.teamA ?? "Équipe A", accentColor: teamAColor, alignment: .leading)
                    Text("vs")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 40)
                        .foregroundStyle(.secondary)
                    MatchTeamPill(title: game.teamB ?? "Équipe B", accentColor: teamBColor, alignment: .trailing)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct MatchRowCard: View {
    let titleOverride: String?
    let subtitleOverride: String?
    let timeOverride: String?
    let pitchOverride: String?
    let clubName: String?
    let leftColor: Color?
    let rightColor: Color?
    let match: MatchLite
    let playerNamesByID: [String: String]
    let showsBackground: Bool

    init(
        titleOverride: String? = nil,
        subtitleOverride: String? = nil,
        timeOverride: String? = nil,
        pitchOverride: String? = nil,
        clubName: String? = nil,
        leftColor: Color? = nil,
        rightColor: Color? = nil,
        match: MatchLite,
        playerNamesByID: [String: String],
        showsBackground: Bool = true
    ) {
        self.titleOverride = titleOverride
        self.subtitleOverride = subtitleOverride
        self.timeOverride = timeOverride
        self.pitchOverride = pitchOverride
        self.clubName = clubName
        self.leftColor = leftColor
        self.rightColor = rightColor
        self.match = match
        self.playerNamesByID = playerNamesByID
        self.showsBackground = showsBackground
    }

    var body: some View {
        HStack(spacing: 14) {
            MatchTeamPill(title: leftLabel, accentColor: leftColor ?? .accentColor, alignment: .trailing)

            Text(centerLabel)
                .font(.headline.weight(.semibold))
                .foregroundStyle(centerLabel == "vs" ? .secondary : .primary)
                .frame(minWidth: 56, alignment: .center)

            MatchTeamPill(title: rightLabel, accentColor: rightColor ?? .secondary, alignment: .leading)
        }
        .padding(.horizontal, showsBackground ? 14 : 0)
        .padding(.vertical, showsBackground ? 10 : 0)
        .background {
            if showsBackground {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemBackground))
            }
        }
    }

    private var leftLabel: String {
        if let titleOverride {
            return titleOverride
        }
        if let clubName, !clubName.isEmpty {
            return clubName
        }
        return "Nous"
    }

    private var rightLabel: String {
        if let subtitleOverride {
            return subtitleOverride
        }
        if let opponentName = match.opponentName, !opponentName.isEmpty {
            return opponentName
        }
        return "Adversaire"
    }

    private var isCancelled: Bool {
        let rawStatus = match.status?.uppercased()
        return rawStatus == "CANCELLED" || rawStatus == "CANCELED" || rawStatus == "ANNULE"
    }

    private var isPlayed: Bool {
        if isCancelled { return false }
        if let played = match.played { return played }
        let home = match.teams.first(where: { $0.side == "home" })?.score ?? 0
        let away = match.teams.first(where: { $0.side == "away" })?.score ?? 0
        return home != 0 || away != 0 || !match.scorers.isEmpty
    }

    private var scoreLabel: String {
        if isCancelled || !isPlayed { return "vs" }
        let home = match.teams.first(where: { $0.side == "home" })?.score ?? 0
        let away = match.teams.first(where: { $0.side == "away" })?.score ?? 0
        return "\(home) - \(away)"
    }

    private var centerLabel: String {
        if isPlayed {
            return scoreLabel
        }
        if let timeLabel {
            return timeLabel
        }
        return "vs"
    }

    private var timeLabel: String? {
        if let timeOverride, !timeOverride.isEmpty {
            return timeOverride
        }
        if let startTime = match.startTime, !startTime.isEmpty {
            return startTime
        }
        return nil
    }

    private var pitchLabel: String? {
        if let pitchOverride, !pitchOverride.isEmpty {
            return formatPitchLabel(pitchOverride)
        }
        if let terrain = match.terrain, !terrain.isEmpty {
            return formatPitchLabel(terrain)
        }
        if let field = match.field, !field.isEmpty {
            return formatPitchLabel(field)
        }
        return nil
    }
}

private struct MatchdayMatchesPagerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let initialMatchID: String
    let matches: [MatchLite]
    let clubName: String?
    let matchdayDate: String
    let playerNamesByID: [String: String]
    let matchProvider: (String) -> MatchLite?

    @State private var selectedMatchID: String
    @StateObject private var sheetViewModel: MatchdayMatchesSheetViewModel

    init(
        initialMatchID: String,
        matches: [MatchLite],
        clubName: String?,
        matchdayDate: String,
        playerNamesByID: [String: String],
        matchProvider: @escaping (String) -> MatchLite?
    ) {
        self.initialMatchID = initialMatchID
        self.matches = matches
        self.clubName = clubName
        self.matchdayDate = matchdayDate
        self.playerNamesByID = playerNamesByID
        self.matchProvider = matchProvider
        _selectedMatchID = State(initialValue: initialMatchID)
        _sheetViewModel = StateObject(
            wrappedValue: MatchdayMatchesSheetViewModel(
                matches: matches,
                fallbackPlayerNamesByID: playerNamesByID
            )
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                TabView(selection: $selectedMatchID) {
                    ForEach(matches) { match in
                        MatchdayMatchDetailView(
                            clubName: clubName,
                            matchdayDate: matchdayDate,
                            matchProvider: matchProvider,
                            viewModel: sheetViewModel.viewModel(for: match.id)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                        .tag(match.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if matches.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(matches) { match in
                            Circle()
                                .fill(match.id == selectedMatchID ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: match.id == selectedMatchID ? 8 : 6, height: match.id == selectedMatchID ? 8 : 6)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Matchs du plateau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task {
                            await sheetViewModel.persistAllChanges()
                            dismiss()
                        }
                    } label: {
                        if sheetViewModel.isPersisting {
                            ProgressView()
                        } else {
                            Image(systemName: "xmark")
                        }
                    }
                    .disabled(sheetViewModel.isPersisting)
                }
            }
        }
        .task {
            await sheetViewModel.loadAll()
        }
        .onDisappear {
            Task {
                await sheetViewModel.persistAllChanges()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(sheetViewModel.isPersisting)
    }
}

private struct MatchdayMatchDetailView: View {
    let clubName: String?
    let matchdayDate: String
    let matchProvider: (String) -> MatchLite?
    @ObservedObject var viewModel: MatchdayMatchDetailViewModel
    @State private var isEditingScore = false

    init(
        clubName: String?,
        matchdayDate: String,
        matchProvider: @escaping (String) -> MatchLite?,
        viewModel: MatchdayMatchDetailViewModel
    ) {
        self.clubName = clubName
        self.matchdayDate = matchdayDate
        self.matchProvider = matchProvider
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if let match = viewModel.matchDetail ?? matchProvider(viewModel.matchID).map(MatchdayMatchDetailViewModel.makeDetailFallback(from:)) {
                List {
                    VStack(alignment: .leading, spacing: 20) {
                        MatchDetailHeroCard(
                            match: match,
                            clubName: clubName,
                            matchdayDate: matchdayDate,
                            playerNamesByID: viewModel.playerNamesByID,
                            availableScorerIDs: viewModel.availableScorerPlayerIDs,
                            scorerDisplayName: { viewModel.displayName(for: $0) },
                            onApplyScoreEdit: { homeScore, awayScore, scorerCounts in
                                viewModel.applyScoreDraft(homeScore: homeScore, awayScore: awayScore, scorerCounts: scorerCounts)
                            },
                            isEditing: $isEditingScore
                        )

                        MatchLineupCard(
                            detail: match,
                            viewModel: viewModel
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .systemGroupedBackground))
                .overlay(alignment: .center) {
                    if viewModel.isLoading {
                        ProgressView("Chargement")
                    }
                }
            } else {
                ContentUnavailableView("Match indisponible", systemImage: "sportscourt", description: Text("Ce match n'est plus disponible."))
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

@MainActor
private final class MatchdayMatchesSheetViewModel: ObservableObject {
    @Published private(set) var isPersisting = false

    private let matches: [MatchLite]
    private let fallbackPlayerNamesByID: [String: String]
    private let api: IzifootAPI
    private var viewModelsByID: [String: MatchdayMatchDetailViewModel] = [:]
    private var hasLoaded = false

    init(matches: [MatchLite], fallbackPlayerNamesByID: [String: String], api: IzifootAPI? = nil) {
        self.matches = matches
        self.fallbackPlayerNamesByID = fallbackPlayerNamesByID
        self.api = api ?? IzifootAPI()
    }

    func viewModel(for matchID: String) -> MatchdayMatchDetailViewModel {
        if let existing = viewModelsByID[matchID] {
            return existing
        }

        let viewModel = MatchdayMatchDetailViewModel(
            matchID: matchID,
            fallbackPlayerNamesByID: fallbackPlayerNamesByID,
            api: api
        )
        viewModelsByID[matchID] = viewModel
        return viewModel
    }

    func loadAll() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        let matchdayID = matches.compactMap(\.matchdayId).first
        async let playersTask = api.allPlayers()
        async let summaryTask: MatchdaySummary? = {
            guard let matchdayID else { return nil }
            return try? await api.matchdaySummary(id: matchdayID, includeAllPlayers: true)
        }()
        async let attendanceTask: [AttendanceRow]? = {
            guard let matchdayID else { return nil }
            return try? await api.allAttendanceBySession(type: "PLATEAU", sessionID: matchdayID)
        }()

        let players = (try? await playersTask) ?? []
        let summary = await summaryTask
        let attendance = await attendanceTask

        for match in matches {
            let viewModel = viewModel(for: match.id)
            await viewModel.load(sharedPlayers: players, summary: summary, attendance: attendance)
        }
    }

    func persistAllChanges() async {
        guard !isPersisting else { return }
        isPersisting = true
        defer { isPersisting = false }

        for match in matches {
            if let viewModel = viewModelsByID[match.id] {
                await viewModel.persistPendingChanges()
            }
        }
    }
}

@MainActor
private final class MatchdayMatchDetailViewModel: ObservableObject {
    private enum CompositionSelection: Equatable {
        case slot(token: String, playerID: String)
        case bench(playerID: String)

        var playerID: String {
            switch self {
            case .slot(_, let playerID), .bench(let playerID):
                return playerID
            }
        }
    }

    @Published private(set) var matchDetail: MatchDetail?
    @Published private(set) var eligiblePlayers: [Player] = []
    @Published private(set) var playerNamesByID: [String: String]
    @Published var selectedPreset: String = "formation:balanced"
    @Published var slotAssignments: [String: String] = [:]
    @Published var tacticPoints: [String: MatchTacticPoint] = [:]
    @Published private var benchOrder: [String] = []
    @Published private var selectedComposition: CompositionSelection?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    let matchID: String
    private let api: IzifootAPI
    private var hasPendingChanges = false

    init(matchID: String, fallbackPlayerNamesByID: [String: String], api: IzifootAPI? = nil) {
        self.matchID = matchID
        self.api = api ?? IzifootAPI()
        self.playerNamesByID = fallbackPlayerNamesByID
    }

    func load(sharedPlayers: [Player]? = nil, summary: MatchdaySummary? = nil, attendance: [AttendanceRow]? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let detail = try await api.match(id: matchID)
            matchDetail = detail

            let resolvedPlayers: [Player]
            let resolvedSummary: MatchdaySummary?
            let resolvedAttendance: [AttendanceRow]?

            if let sharedPlayers {
                resolvedPlayers = sharedPlayers
                resolvedSummary = summary
                resolvedAttendance = attendance
            } else {
                async let playersTask = api.allPlayers()
                async let summaryTask: MatchdaySummary? = {
                    guard let matchdayId = detail.matchdayId else { return nil }
                    return try? await api.matchdaySummary(id: matchdayId, includeAllPlayers: true)
                }()
                async let attendanceTask: [AttendanceRow]? = {
                    guard let matchdayId = detail.matchdayId else { return nil }
                    return try? await api.allAttendanceBySession(type: "PLATEAU", sessionID: matchdayId)
                }()

                resolvedPlayers = (try? await playersTask) ?? []
                resolvedSummary = await summaryTask
                resolvedAttendance = await attendanceTask
            }

            let eligibleIDs = eligiblePlayerIDs(detail: detail, summary: resolvedSummary, attendance: resolvedAttendance)
            let summaryNames = Dictionary(
                uniqueKeysWithValues: (resolvedSummary?.convocations ?? [])
                    .compactMap { convocation -> (String, String)? in
                        guard !convocation.playerId.isEmpty else { return nil }
                        guard let playerName = convocation.playerName, !playerName.isEmpty else { return nil }
                        return (convocation.playerId, playerName)
                    }
            )

            let fetchedEligiblePlayers = resolvedPlayers
                .filter { eligibleIDs.contains($0.id) }
            let fetchedEligibleIDs = Set(fetchedEligiblePlayers.map(\.id))
            let fallbackEligiblePlayers = eligibleIDs
                .filter { !$0.isEmpty && !fetchedEligibleIDs.contains($0) }
                .map { playerID in
                    Player(
                        id: playerID,
                        name: summaryNames[playerID]
                            ?? detail.homePlayers.first(where: { $0.playerId == playerID })?.playerName
                            ?? playerNamesByID[playerID]
                            ?? "Joueur"
                    )
                }

            eligiblePlayers = (fetchedEligiblePlayers + fallbackEligiblePlayers)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            let extraNames = Dictionary(uniqueKeysWithValues: eligiblePlayers.map { ($0.id, $0.name) })
            playerNamesByID.merge(extraNames) { _, new in new }
            playerNamesByID.merge(summaryNames) { _, new in new }
            for player in detail.homePlayers {
                if let name = player.playerName, !name.isEmpty {
                    playerNamesByID[player.playerId] = name
                }
            }

            rebuildComposition(from: detail)
            hasPendingChanges = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isSelected(playerID: String) -> Bool {
        selectedComposition?.playerID == playerID
    }

    func selectBenchPlayer(_ playerID: String) {
        let tappedSelection = CompositionSelection.bench(playerID: playerID)

        guard let selectedComposition else {
            self.selectedComposition = tappedSelection
            return
        }

        if selectedComposition == tappedSelection {
            self.selectedComposition = nil
            return
        }

        switch selectedComposition {
        case .bench(let selectedPlayerID):
            swapBenchPlayers(selectedPlayerID, playerID)
        case .slot(let token, let selectedPlayerID):
            var nextAssignments = slotAssignments
            nextAssignments[token] = playerID
            slotAssignments = sanitizedAssignments(nextAssignments)
            replaceBenchPlayer(playerID, with: selectedPlayerID)
        }

        self.selectedComposition = nil
        markCompositionChanged()
    }

    func selectSlot(_ token: String) {
        if let tappedPlayerID = slotAssignments[token] {
            let tappedSelection = CompositionSelection.slot(token: token, playerID: tappedPlayerID)

            guard let selectedComposition else {
                self.selectedComposition = tappedSelection
                return
            }

            if selectedComposition == tappedSelection {
                self.selectedComposition = nil
                return
            }

            switch selectedComposition {
            case .slot(let selectedToken, let selectedPlayerID):
                var nextAssignments = slotAssignments
                nextAssignments[selectedToken] = tappedPlayerID
                nextAssignments[token] = selectedPlayerID
                slotAssignments = sanitizedAssignments(nextAssignments)
            case .bench(let selectedPlayerID):
                var nextAssignments = slotAssignments.filter { $0.value != selectedPlayerID }
                nextAssignments[token] = selectedPlayerID
                slotAssignments = sanitizedAssignments(nextAssignments)
                updateBenchOrderAfterMovingBenchPlayer(selectedPlayerID, into: token, displacedPlayerID: tappedPlayerID)
            }
        } else {
            guard let selectedComposition else { return }

            switch selectedComposition {
            case .slot(let selectedToken, let selectedPlayerID):
                var nextAssignments = slotAssignments
                nextAssignments[selectedToken] = nil
                nextAssignments[token] = selectedPlayerID
                slotAssignments = sanitizedAssignments(nextAssignments)
            case .bench(let selectedPlayerID):
                var nextAssignments = slotAssignments.filter { $0.value != selectedPlayerID }
                nextAssignments[token] = selectedPlayerID
                slotAssignments = sanitizedAssignments(nextAssignments)
                updateBenchOrderAfterMovingBenchPlayer(selectedPlayerID, into: token, displacedPlayerID: nil)
            }
        }

        guard selectedComposition != nil else {
            return
        }

        self.selectedComposition = nil
        markCompositionChanged()
    }

    func updatePreset(_ preset: String) {
        selectedPreset = preset
        tacticPoints = defaultPoints(tokens: tokens, playersOnField: playersOnField, preset: preset)
        markCompositionChanged()
    }

    var playersOnField: Int {
        guard let detail = matchDetail else { return 5 }
        let startersCount = detail.homeStarters.count
        if [3, 5, 8, 11].contains(startersCount) {
            return startersCount
        }
        if let presetCount = playersOnFieldFromPreset(selectedPreset) {
            return presetCount
        }
        return 5
    }

    var tokens: [String] {
        guard playersOnField > 0 else { return [] }
        return ["gk"] + (1..<playersOnField).map { "p\($0)" }
    }

    var benchPlayerIDs: [String] {
        let currentBenchSet = Set(currentBenchPool)
        let orderedBench = benchOrder.filter { currentBenchSet.contains($0) }
        let remainingBench = currentBenchPool.filter { !orderedBench.contains($0) }
        return orderedBench + remainingBench
    }

    var presetOptions: [LineupPresetOption] {
        switch playersOnField {
        case 3:
            return [.init(id: "formation:balanced", title: "Équilibré")]
        case 5:
            return [
                .init(id: "formation:diamond", title: "Losange"),
                .init(id: "formation:balanced", title: "Équilibré"),
                .init(id: "formation:square", title: "Carré")
            ]
        case 8:
            return [
                .init(id: "formation:balanced", title: "Équilibré"),
                .init(id: "formation:3-3-1", title: "3-3-1")
            ]
        case 11:
            return [
                .init(id: "formation:4-3-3", title: "4-3-3"),
                .init(id: "formation:4-4-2", title: "4-4-2"),
                .init(id: "formation:balanced", title: "Équilibré")
            ]
        default:
            return [.init(id: "formation:balanced", title: "Équilibré")]
        }
    }

    func displayName(for playerID: String) -> String {
        playerNamesByID[playerID] ?? eligiblePlayers.first(where: { $0.id == playerID })?.name ?? "Joueur"
    }

    func shortDisplayName(for playerID: String) -> String {
        abbreviatedDisplayName(displayName(for: playerID))
    }

    func playerColor(for playerID: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.76, green: 0.24, blue: 0.20),
            Color(red: 0.18, green: 0.49, blue: 0.74),
            Color(red: 0.50, green: 0.23, blue: 0.88),
            Color(red: 0.89, green: 0.57, blue: 0.16),
            Color(red: 0.20, green: 0.67, blue: 0.46),
            Color(red: 0.75, green: 0.39, blue: 0.18),
            Color(red: 0.85, green: 0.27, blue: 0.58),
            Color(red: 0.17, green: 0.63, blue: 0.69)
        ]
        let index = abs(playerID.hashValue) % palette.count
        return palette[index]
    }

    func point(for token: String) -> MatchTacticPoint {
        tacticPoints[token] ?? MatchTacticPoint(x: 50, y: 50)
    }

    var availableScorerPlayerIDs: [String] {
        unique(tokens.compactMap { slotAssignments[$0] } + benchPlayerIDs)
    }

    func goalCount(for playerID: String) -> Int {
        guard let matchDetail else { return 0 }
        return matchDetail.scorers.filter { $0.side == "home" && $0.playerId == playerID }.count
    }

    func applyScoreDraft(homeScore: Int, awayScore: Int, scorerCounts: [String: Int]) {
        guard let detail = matchDetail else { return }

        let updatedTeams = detail.teams.map { team in
            switch team.side {
            case "home":
                MatchDetailTeam(id: team.id, side: team.side, score: homeScore, players: team.players)
            case "away":
                MatchDetailTeam(id: team.id, side: team.side, score: awayScore, players: team.players)
            default:
                team
            }
        }

        let updatedHomeScorers = scorerCounts
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                let leftName = displayName(for: lhs.key)
                let rightName = displayName(for: rhs.key)
                return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
            }
            .flatMap { playerID, count in
                Array(repeating: MatchScorer(
                    playerId: playerID,
                    side: "home",
                    playerName: displayName(for: playerID)
                ), count: count)
            }

        matchDetail = MatchDetail(
            id: detail.id,
            type: detail.type,
            matchdayId: detail.matchdayId,
            opponentName: detail.opponentName,
            played: true,
            status: detail.status,
            rotationGameKey: detail.rotationGameKey,
            teams: updatedTeams,
            scorers: updatedHomeScorers + detail.scorers.filter { $0.side != "home" },
            tactic: detail.tactic,
            startTime: detail.startTime,
            terrain: detail.terrain,
            field: detail.field
        )
        hasPendingChanges = true
    }

    private func abbreviatedDisplayName(_ name: String) -> String {
        let parts = name
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let firstName = parts.first else { return name }
        guard parts.count > 1, let initial = parts[1].first else { return firstName }
        return "\(firstName) \(String(initial))."
    }

    static func makeDetailFallback(from match: MatchLite) -> MatchDetail {
        MatchDetail(
            id: match.id,
            type: match.type,
            matchdayId: match.matchdayId,
            opponentName: match.opponentName,
            played: match.played,
            status: match.status,
            rotationGameKey: match.rotationGameKey,
            teams: match.teams.map {
                MatchDetailTeam(id: $0.id, side: $0.side, score: $0.score, players: [])
            },
            scorers: match.scorers,
            tactic: nil,
            startTime: match.startTime,
            terrain: match.terrain,
            field: match.field
        )
    }

    private func rebuildComposition(from detail: MatchDetail) {
        let playersOnField = self.playersOnField
        let tokens = (["gk"] + (1..<playersOnField).map { "p\($0)" })
        let starters = Array(detail.homeStarters.prefix(playersOnField))
        var assignments: [String: String] = [:]
        for (token, player) in zip(tokens, starters) {
            assignments[token] = player.playerId
        }
        slotAssignments = assignments
        benchOrder = currentBenchPool(for: detail, assignments: assignments)
        selectedComposition = nil

        selectedPreset = detail.tactic?.preset ?? preferredPreset(for: playersOnField)
        tacticPoints = {
            if let points = detail.tactic?.points, !points.isEmpty {
                return points
            }
            return defaultPoints(tokens: tokens, playersOnField: playersOnField, preset: selectedPreset)
        }()
    }

    private func markCompositionChanged() {
        hasPendingChanges = true
    }

    func persistPendingChanges() async {
        guard hasPendingChanges else { return }
        guard let detail = matchDetail, let matchdayId = detail.matchdayId else { return }
        isSaving = true
        defer { isSaving = false }

        let homeStarters = tokens.compactMap { slotAssignments[$0] }
        let homeSubs = benchPlayerIDs
        let awayStarters = detail.awayStarters.map(\.playerId)
        let awaySubs = detail.awaySubs.map(\.playerId)

        let payload = MatchPayload(
            type: detail.type,
            matchdayId: matchdayId,
            sides: MatchSidesPayload(
                home: MatchSidePlayersPayload(starters: Array(homeStarters.prefix(playersOnField)), subs: homeSubs),
                away: MatchSidePlayersPayload(starters: awayStarters, subs: awaySubs)
            ),
            score: MatchScorePayload(
                home: detail.teams.first(where: { $0.side == "home" })?.score ?? 0,
                away: detail.teams.first(where: { $0.side == "away" })?.score ?? 0
            ),
            buteurs: detail.scorers.map { MatchScorerPayload(playerId: $0.playerId, side: $0.side, assistId: $0.assistId) },
            opponentName: detail.opponentName ?? "",
            played: detail.played ?? false,
            rotationGameKey: detail.rotationGameKey,
            tactic: MatchTacticPayload(
                preset: selectedPreset,
                points: Dictionary(uniqueKeysWithValues: tokens.map { token in
                    let point = tacticPoints[token] ?? MatchTacticPoint(x: 50, y: 50)
                    return (token, MatchTacticPointPayload(x: point.x, y: point.y))
                })
            )
        )

        do {
            _ = try await api.updateMatch(id: detail.id, payload: payload)
            hasPendingChanges = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func eligiblePlayerIDs(detail: MatchDetail, summary: MatchdaySummary?, attendance: [AttendanceRow]?) -> Set<String> {
        let excludedStatuses = Set(["absent", "non_convoque", "non convoque", "non-convoque"])
        let fromSummary = Set(
            (summary?.convocations ?? [])
                .filter {
                    let normalizedStatus = $0.status
                        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        .replacingOccurrences(of: "-", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return !$0.playerId.isEmpty && !normalizedStatus.isEmpty && !excludedStatuses.contains(normalizedStatus)
                }
                .map(\.playerId)
        )
        let fromAttendance = Set(
            (attendance ?? [])
                .filter(\.present)
                .filter { !$0.playerId.isEmpty }
                .map(\.playerId)
        )
        let currentHome = Set(detail.homePlayers.map(\.playerId).filter { !$0.isEmpty })
        let plateauPlayers = fromAttendance.isEmpty ? fromSummary : fromAttendance.union(fromSummary)
        return plateauPlayers.isEmpty ? currentHome : plateauPlayers.union(currentHome)
    }

    private var currentBenchPool: [String] {
        currentBenchPool(for: matchDetail, assignments: slotAssignments)
    }

    private func currentBenchPool(for detail: MatchDetail?, assignments: [String: String]) -> [String] {
        let assigned = Set(assignments.values)
        let eligibleIDs = Set(eligiblePlayers.map(\.id))
        let currentHomeIDs = Set(detail?.homePlayers.map(\.playerId) ?? [])
        let orderedPool = eligiblePlayers.map(\.id) + (detail?.homePlayers.map(\.playerId) ?? [])
        return unique(orderedPool.filter {
            (eligibleIDs.isEmpty || eligibleIDs.contains($0) || currentHomeIDs.contains($0)) && !assigned.contains($0)
        })
    }

    private func updateBenchOrderAfterMovingBenchPlayer(_ benchPlayerID: String, into token: String, displacedPlayerID: String?) {
        guard let index = benchOrder.firstIndex(of: benchPlayerID) else {
            if let displacedPlayerID, !benchOrder.contains(displacedPlayerID) {
                benchOrder.append(displacedPlayerID)
            }
            return
        }

        if let displacedPlayerID {
            benchOrder[index] = displacedPlayerID
        } else {
            benchOrder.remove(at: index)
        }
    }

    private func replaceBenchPlayer(_ targetPlayerID: String, with replacementPlayerID: String) {
        if let index = benchOrder.firstIndex(of: targetPlayerID) {
            benchOrder[index] = replacementPlayerID
        } else if !benchOrder.contains(replacementPlayerID) {
            benchOrder.append(replacementPlayerID)
        }
    }

    private func swapBenchPlayers(_ firstPlayerID: String, _ secondPlayerID: String) {
        guard let firstIndex = benchOrder.firstIndex(of: firstPlayerID),
              let secondIndex = benchOrder.firstIndex(of: secondPlayerID) else { return }
        benchOrder.swapAt(firstIndex, secondIndex)
    }

    private func sanitizedAssignments(_ assignments: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        var used = Set<String>()
        for token in tokens {
            guard let playerID = assignments[token], !used.contains(playerID) else { continue }
            result[token] = playerID
            used.insert(playerID)
        }
        return result
    }

    private func preferredPreset(for playersOnField: Int) -> String {
        switch playersOnField {
        case 5: return "formation:diamond"
        case 8: return "formation:3-3-1"
        case 11: return "formation:4-3-3"
        default: return "formation:balanced"
        }
    }

    private func playersOnFieldFromPreset(_ preset: String) -> Int? {
        if preset.contains("11") { return 11 }
        if preset.contains("8") { return 8 }
        if preset.contains("5") || preset.contains("diamond") || preset.contains("square") || preset.contains("balanced") { return 5 }
        if preset.contains("3") { return 3 }
        return nil
    }
}

private extension MatchDetail {
    var homeTeam: MatchDetailTeam? { teams.first(where: { $0.side == "home" }) }
    var awayTeam: MatchDetailTeam? { teams.first(where: { $0.side == "away" }) }
    var homePlayers: [MatchDetailTeamPlayer] { homeTeam?.players ?? [] }
    var homeStarters: [MatchDetailTeamPlayer] {
        hasPersistedHomeComposition ? homePlayers.filter { isStarterRole($0.role) } : []
    }
    var homeSubs: [MatchDetailTeamPlayer] {
        hasPersistedHomeComposition ? homePlayers.filter { isBenchRole($0.role) } : []
    }
    var awayStarters: [MatchDetailTeamPlayer] {
        let awayPlayers = awayTeam?.players ?? []
        let hasExplicitRoles = awayPlayers.contains { isStarterRole($0.role) || isBenchRole($0.role) }
        return hasExplicitRoles ? awayPlayers.filter { isStarterRole($0.role) } : awayPlayers
    }
    var awaySubs: [MatchDetailTeamPlayer] {
        let awayPlayers = awayTeam?.players ?? []
        let hasExplicitRoles = awayPlayers.contains { isStarterRole($0.role) || isBenchRole($0.role) }
        return hasExplicitRoles ? awayPlayers.filter { isBenchRole($0.role) } : []
    }

    private var hasPersistedHomeComposition: Bool {
        homePlayers.contains { isStarterRole($0.role) || isBenchRole($0.role) }
    }

    private func isStarterRole(_ role: String) -> Bool {
        let normalized = normalizedRole(role)
        return ["starter", "starting", "titulaire"].contains(normalized)
    }

    private func isBenchRole(_ role: String) -> Bool {
        let normalized = normalizedRole(role)
        return ["sub", "bench", "remplacant"].contains(normalized)
    }

    private func normalizedRole(_ role: String) -> String {
        role
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct LineupPresetOption: Identifiable, Hashable {
    let id: String
    let title: String
}

private struct MatchLineupCard: View {
    let detail: MatchDetail
    @ObservedObject var viewModel: MatchdayMatchDetailViewModel

    var body: some View {
        DetailCard {
            HStack(alignment: .center, spacing: 12) {
                SectionHeaderLabel(title: "Composition", systemImage: "soccerball.inverse")
                Spacer()
                if viewModel.isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Picker("Tactique", selection: Binding(
                get: { viewModel.selectedPreset },
                set: { viewModel.updatePreset($0) }
            )) {
                ForEach(viewModel.presetOptions) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .pickerStyle(.menu)

            MatchLineupPitchView(viewModel: viewModel)

            VStack(alignment: .leading, spacing: 10) {
                Text("Remplaçants")
                    .font(.headline)

                MatchBenchView(viewModel: viewModel)
            }
        }
    }
}

private struct MatchLineupPitchView: View {
    @ObservedObject var viewModel: MatchdayMatchDetailViewModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.29, green: 0.58, blue: 0.31), Color(red: 0.36, green: 0.65, blue: 0.39)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Rectangle()
                    .fill(.white.opacity(0.5))
                    .frame(height: 2)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                Circle()
                    .stroke(.white.opacity(0.45), lineWidth: 2)
                    .frame(width: min(proxy.size.width, proxy.size.height) * 0.24)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                ForEach(viewModel.tokens, id: \.self) { token in
                    let point = viewModel.point(for: token)
                    let playerID = viewModel.slotAssignments[token]
                    MatchLineupSlotView(
                        playerID: playerID,
                        playerName: playerID.map(viewModel.shortDisplayName(for:)),
                        playerColor: playerID.map(viewModel.playerColor(for:)),
                        isSelected: playerID.map(viewModel.isSelected(playerID:)) ?? false,
                        onTap: {
                            viewModel.selectSlot(token)
                        }
                    )
                    .position(
                        x: proxy.size.width * CGFloat(point.x / 100),
                        y: proxy.size.height * CGFloat(point.y / 100)
                    )
                }
            }
        }
        .frame(height: 430)
    }
}

private struct MatchLineupSlotView: View {
    let playerID: String?
    let playerName: String?
    let playerColor: Color?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill((playerColor ?? .white).opacity(playerColor == nil ? 0.16 : 0.96))
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.8), lineWidth: 2)
                    )
                    .overlay(
                        Circle()
                            .stroke(.yellow.opacity(isSelected ? 0.95 : 0), lineWidth: 4)
                    )

                if let playerName {
                    Text(initials(from: playerName))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            if let playerName {
                Text(playerName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 92)
            }
        }
        .padding(8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

private struct MatchBenchView: View {
    @ObservedObject var viewModel: MatchdayMatchDetailViewModel

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(viewModel.benchPlayerIDs, id: \.self) { playerID in
                MatchBenchPlayerView(
                    playerID: playerID,
                    displayName: viewModel.shortDisplayName(for: playerID),
                    playerColor: viewModel.playerColor(for: playerID),
                    isSelected: viewModel.isSelected(playerID: playerID)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture {
                    viewModel.selectBenchPlayer(playerID)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

private struct MatchBenchPlayerView: View {
    let playerID: String
    let displayName: String
    let playerColor: Color
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(playerColor.opacity(0.94))
                .frame(width: 50, height: 50)
                .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 3)
                .overlay(
                    Text(initials)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                )
                .overlay(
                    Circle()
                        .stroke(.yellow.opacity(isSelected ? 0.95 : 0), lineWidth: 3)
                )

            Text(displayName)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

private func layoutRows(for playersOnField: Int, preset: String) -> [Int] {
    switch playersOnField {
    case 3:
        return [1, 1]
    case 5:
        if preset.contains("square") { return [2, 2] }
        return [1, 2, 1]
    case 8:
        return [3, 3, 1]
    case 11:
        if preset.contains("4-4-2") { return [4, 4, 2] }
        return [4, 3, 3]
    default:
        return [1, 2, 1]
    }
}

private func defaultPoints(tokens: [String], playersOnField: Int, preset: String) -> [String: MatchTacticPoint] {
    guard !tokens.isEmpty else { return [:] }
    var points: [String: MatchTacticPoint] = ["gk": MatchTacticPoint(x: 50, y: 90)]
    let rows = layoutRows(for: playersOnField, preset: preset)
    let yValues = rows.count == 1 ? [45.0] : stride(from: 72.0, through: 28.0, by: -(44.0 / Double(max(rows.count - 1, 1)))).map { $0 }

    var tokenIndex = 1
    for (rowIndex, rowCount) in rows.enumerated() {
        let y = rowIndex < yValues.count ? yValues[rowIndex] : 50.0
        let xs: [Double]
        if rowCount == 1 {
            xs = [50]
        } else {
            let step = 64.0 / Double(rowCount - 1)
            xs = (0..<rowCount).map { 18.0 + (Double($0) * step) }
        }
        for x in xs where tokenIndex < tokens.count {
            points[tokens[tokenIndex]] = MatchTacticPoint(x: x, y: y)
            tokenIndex += 1
        }
    }
    return points
}

private func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
}

private struct MatchDetailHeroCard: View {
    let match: MatchDetail
    let clubName: String?
    let matchdayDate: String
    let playerNamesByID: [String: String]
    let availableScorerIDs: [String]
    let scorerDisplayName: (String) -> String
    let onApplyScoreEdit: (Int, Int, [String: Int]) -> Void
    @Binding var isEditing: Bool

    @State private var draftHomeScore: Int = 0
    @State private var draftAwayScore: Int = 0
    @State private var scorerCounts: [String: Int] = [:]
    @State private var flipAngle: Double = 0
    @State private var shouldUseExpandedLayout = false
    @State private var stagedAnimationTask: Task<Void, Never>?

    var body: some View {
        layoutFace
            .opacity(0.001)
            .overlay {
                ZStack {
                    heroFront
                        .rotation3DEffect(
                            .degrees(safeFlipAngle(flipAngle)),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.75
                        )
                        .opacity(flipAngle < 90 ? 1 : 0)

                    heroBack
                        .rotation3DEffect(
                            .degrees(safeFlipAngle(flipAngle - 180)),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.75
                        )
                        .opacity(flipAngle >= 90 ? 1 : 0)
                }
            }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.34), value: shouldUseExpandedLayout)
        .onAppear(perform: syncDraftFromMatch)
        .onChange(of: match.id) { _, _ in
            stagedAnimationTask?.cancel()
            syncDraftFromMatch()
            isEditing = false
            flipAngle = 0
            shouldUseExpandedLayout = false
        }
        .onChange(of: match.scorers.map(\.playerId).joined(separator: "|")) { _, _ in
            syncDraftFromMatch()
        }
        .onChange(of: homeScore) { _, _ in
            if !isEditing {
                syncDraftFromMatch()
            }
        }
        .onChange(of: awayScore) { _, _ in
            if !isEditing {
                syncDraftFromMatch()
            }
        }
        .onChange(of: isEditing) { _, newValue in
            stagedAnimationTask?.cancel()
            if newValue {
                shouldUseExpandedLayout = false
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                    flipAngle = 180
                }
                stagedAnimationTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 140_000_000)
                    guard isEditing else { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                        shouldUseExpandedLayout = true
                    }
                }
            } else {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
                    shouldUseExpandedLayout = false
                }
                stagedAnimationTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    guard !isEditing else { return }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                        flipAngle = 0
                    }
                }
            }
        }
    }

    private var layoutFace: some View {
        Group {
            if shouldUseExpandedLayout {
                heroBack
            } else {
                heroFront
            }
        }
    }

    private var heroFront: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                MatchDetailTeamColumn(name: homeTeamName)

                Text(centerPrimaryLabel)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(minWidth: 72)
                    .padding(.top, 10)

                MatchDetailTeamColumn(name: awayTeamName)
            }

            if !homeScorers.isEmpty {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(homeScorers, id: \.self) { scorerName in
                            HStack(spacing: 6) {
                                Image(systemName: "soccerball")
                                    .font(.subheadline)
                                Text(scorerName)
                                    .font(.title3.weight(.medium))
                            }
                            .foregroundStyle(.white.opacity(0.92))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            Text(centerSecondaryLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.12))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )

            Text(DateFormatters.displayDateOnly(matchdayDate))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture {
            isEditing = true
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background(heroBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var heroBack: some View {
        VStack(alignment: .leading, spacing: 18) {
            scoreEditorRow(title: homeTeamName, score: $draftHomeScore)
            scoreEditorRow(title: awayTeamName, score: $draftAwayScore)

            VStack(alignment: .leading, spacing: 12) {
                Text("Buteurs")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                if availableScorerIDs.isEmpty {
                    Text("Aucun joueur disponible pour ce match.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                } else {
                    ForEach(availableScorerIDs, id: \.self) { playerID in
                        scorerCounterRow(playerID: playerID)
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    syncDraftFromMatch()
                    isEditing = false
                } label: {
                    Text("Annuler")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onApplyScoreEdit(draftHomeScore, draftAwayScore, scorerCounts)
                    isEditing = false
                } label: {
                    Text("Valider")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var heroBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.33, blue: 0.55),
                Color(red: 0.11, green: 0.24, blue: 0.36),
                Color(red: 0.13, green: 0.37, blue: 0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var isCancelled: Bool {
        let status = match.status?.uppercased()
        return status == "CANCELLED" || status == "CANCELED" || status == "ANNULE"
    }

    private var isPlayed: Bool {
        if isCancelled { return false }
        if let played = match.played { return played }
        return !match.scorers.isEmpty || homeScore != 0 || awayScore != 0
    }

    private var homeScore: Int {
        match.teams.first(where: { $0.side == "home" })?.score ?? 0
    }

    private var homeTeamName: String {
        clubName?.isEmpty == false ? clubName! : "Nous"
    }

    private var awayScore: Int {
        match.teams.first(where: { $0.side == "away" })?.score ?? 0
    }

    private var awayTeamName: String {
        match.opponentName ?? "Adversaire"
    }

    private var centerPrimaryLabel: String {
        if isPlayed {
            return "\(homeScore) - \(awayScore)"
        }
        return "vs"
    }

    private var centerSecondaryLabel: String {
        if isCancelled {
            return "Annulé"
        }
        if isPlayed {
            return homeScore > awayScore ? "Victoire" : homeScore < awayScore ? "Défaite" : "Match nul"
        }
        return "Pas encore joué"
    }

    private var homeScorers: [String] {
        match.scorers
            .filter { $0.side == "home" }
            .map { scorer in
                scorer.playerName ?? playerNamesByID[scorer.playerId] ?? "Joueur inconnu"
            }
    }

    private func scoreEditorRow(title: String, score: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                scoreStepperButton(systemName: "minus") {
                    score.wrappedValue = max(0, score.wrappedValue - 1)
                }

                Text("\(score.wrappedValue)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(minWidth: 44)

                scoreStepperButton(systemName: "plus") {
                    score.wrappedValue = min(30, score.wrappedValue + 1)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func scorerCounterRow(playerID: String) -> some View {
        HStack(spacing: 12) {
            Text(scorerDisplayName(playerID))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)

            scoreStepperButton(systemName: "minus", compact: true) {
                let current = scorerCounts[playerID] ?? 0
                scorerCounts[playerID] = max(0, current - 1)
            }

            Text("\(scorerCounts[playerID] ?? 0)")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(minWidth: 24)

            scoreStepperButton(systemName: "plus", compact: true) {
                let current = scorerCounts[playerID] ?? 0
                scorerCounts[playerID] = min(20, current + 1)
            }
        }
    }

    private func scoreStepperButton(systemName: String, compact: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: compact ? 12 : 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: compact ? 28 : 36, height: compact ? 28 : 36)
                .background(
                    Circle()
                        .fill(.white.opacity(0.14))
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func syncDraftFromMatch() {
        draftHomeScore = homeScore
        draftAwayScore = awayScore
        scorerCounts = Dictionary(
            uniqueKeysWithValues: availableScorerIDs.map { playerID in
                let count = match.scorers.filter { $0.side == "home" && $0.playerId == playerID }.count
                return (playerID, count)
            }
        )
        if !isEditing {
            flipAngle = 0
            shouldUseExpandedLayout = false
        }
    }

    private func safeFlipAngle(_ angle: Double) -> Double {
        let singularThreshold = 0.001
        let normalized = angle.truncatingRemainder(dividingBy: 360)
        if abs(abs(normalized) - 90) < singularThreshold {
            return normalized > 0 ? 89.999 : -89.999
        }
        if abs(abs(normalized) - 270) < singularThreshold {
            return normalized > 0 ? 269.999 : -269.999
        }
        return normalized
    }
}

private struct MatchDetailTeamColumn: View {
    let name: String

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Text(name)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MatchDetailInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct MatchTeamPill: View {
    let title: String
    let accentColor: Color
    let alignment: Alignment

    var body: some View {
        HStack(spacing: 8) {
            if alignment == .leading {
                Circle()
                    .fill(accentColor)
                    .frame(width: 16, height: 16)
            }

            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)

            if alignment == .trailing {
                Circle()
                    .fill(accentColor)
                    .frame(width: 16, height: 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }
}

private func formatPitchLabel(_ rawValue: String) -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return "Terrain à définir"
    }

    let lowered = trimmed.lowercased()

    if lowered.hasPrefix("terrain ") {
        return "Terrain " + trimmed.dropFirst("terrain ".count)
    }

    if lowered.hasPrefix("pitch ") {
        return "Terrain " + trimmed.dropFirst("pitch ".count)
    }

    if let number = Int(trimmed) {
        return "Terrain \(number)"
    }

    return trimmed
}

private struct ManualMatchEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let draft: ManualMatchDraft
    let players: [Player]
    let isSaving: Bool
    let existingMatch: MatchLite?
    let onSave: (ManualMatchDraft) async -> Bool

    @State private var localDraft: ManualMatchDraft

    init(
        draft: ManualMatchDraft,
        players: [Player],
        isSaving: Bool,
        existingMatch: MatchLite?,
        onSave: @escaping (ManualMatchDraft) async -> Bool
    ) {
        self.draft = draft
        self.players = players
        self.isSaving = isSaving
        self.existingMatch = existingMatch
        self.onSave = onSave
        _localDraft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Match") {
                    TextField("Adversaire", text: $localDraft.opponentName)
                    Toggle("Match joué", isOn: $localDraft.played)
                }

                if localDraft.played {
                    Section("Score") {
                        Stepper("Nous: \(localDraft.homeScore)", value: $localDraft.homeScore, in: 0...30)
                        Stepper("Adversaire: \(localDraft.awayScore)", value: $localDraft.awayScore, in: 0...30)
                    }

                    Section("Buteurs") {
                        ForEach(players) { player in
                            Button {
                                toggleScorer(player.id)
                            } label: {
                                HStack {
                                    Text(player.name)
                                    Spacer()
                                    if localDraft.scorerIDs.contains(player.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

            }
            .navigationTitle(existingMatch == nil ? "Ajouter un match" : "Modifier le match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let didSave = await onSave(localDraft)
                            if didSave { dismiss() }
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Valider")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func toggleScorer(_ playerID: String) {
        if let index = localDraft.scorerIDs.firstIndex(of: playerID) {
            localDraft.scorerIDs.remove(at: index)
        } else {
            localDraft.scorerIDs.append(playerID)
        }
    }
}

private struct PlanningEditorSheet: View {
    @Binding var isPresented: Bool
    let initialData: PlanningData?
    let clubName: String?
    let isSaving: Bool
    let onSave: (PlanningData) async -> Bool

    @State private var startTime: Date
    @State private var pitches: Int
    @State private var matchMin: Int
    @State private var breakMin: Int
    @State private var matchesPerTeam: Int
    @State private var maxConsecutiveMatches: Int
    @State private var allowsIntraClubMatches: Bool
    @State private var allowRematches: Bool
    @State private var regenSeed: Int
    @State private var teamNames: [String]
    @State private var newTeamName: String
    @State private var isSubmitting = false

    init(
        isPresented: Binding<Bool>,
        initialData: PlanningData?,
        clubName: String?,
        isSaving: Bool,
        onSave: @escaping (PlanningData) async -> Bool
    ) {
        _isPresented = isPresented
        self.initialData = initialData
        self.clubName = clubName
        self.isSaving = isSaving
        self.onSave = onSave
        let initialTeamNames = initialData?.teams.map(\.label) ?? (clubName.map { ["\($0) 1", "\($0) 2"] } ?? [])
        _startTime = State(initialValue: Self.time(from: initialData?.start ?? "10:00"))
        _pitches = State(initialValue: initialData?.pitches ?? 3)
        _matchMin = State(initialValue: initialData?.matchMin ?? 10)
        _breakMin = State(initialValue: initialData?.breakMin ?? 2)
        _matchesPerTeam = State(initialValue: initialData?.matchesPerTeam ?? 3)
        _maxConsecutiveMatches = State(initialValue: initialData?.restEveryX ?? 2)
        _allowsIntraClubMatches = State(initialValue: !(initialData?.forbidIntraClub ?? false))
        _allowRematches = State(initialValue: initialData?.allowRematches ?? false)
        _regenSeed = State(initialValue: initialData?.regenSeed ?? Int.random(in: 1...Int.max))
        _teamNames = State(initialValue: initialTeamNames)
        _newTeamName = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Paramètres") {
                    DatePicker("Heure de début", selection: $startTime, displayedComponents: .hourAndMinute)
                    Stepper("Terrains: \(pitches)", value: $pitches, in: 1...8)
                    Stepper("Durée match: \(matchMin) min", value: $matchMin, in: 5...60)
                    Stepper("Pause: \(breakMin) min", value: $breakMin, in: 0...20)
                    Stepper("Nombre max de matchs par équipe: \(matchesPerTeam)", value: $matchesPerTeam, in: 1...20)
                    Stepper("Nombre max de matchs d'affilée: \(maxConsecutiveMatches)", value: $maxConsecutiveMatches, in: 1...10)
                    Toggle("Autoriser les matchs entre équipes d'un même club", isOn: $allowsIntraClubMatches)
                    Toggle("Autoriser les rematchs", isOn: $allowRematches)
                }

                Section("Équipes") {
                    if teamNames.isEmpty {
                        Text("Aucune équipe pour le moment")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(teamNames.enumerated()), id: \.offset) { index, teamName in
                            Text(teamName)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        removeTeam(at: index)
                                    } label: {
                                        Label("Supprimer", systemImage: "trash")
                                    }
                                }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ajouter une équipe")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            TextField("Nom de l'équipe", text: $newTeamName)

                            Button("Ajouter") {
                                addTeam()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving || trimmedNewTeamName.isEmpty)
                        }
                    }
                }

                if !generatedSlots.isEmpty {
                    Section {
                        ForEach(generatedSlots.prefix(6)) { slot in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(slot.time)
                                    .font(.subheadline.weight(.semibold))
                                ForEach(slot.games) { game in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Terrain \(game.pitch)")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)

                                        HStack(spacing: 12) {
                                            MatchTeamPill(
                                                title: game.a,
                                                accentColor: teamColor(for: game.a),
                                                alignment: .leading
                                            )
                                            Text("vs")
                                                .font(.subheadline.weight(.semibold))
                                                .frame(minWidth: 40)
                                                .foregroundStyle(.secondary)
                                            MatchTeamPill(
                                                title: game.b,
                                                accentColor: teamColor(for: game.b),
                                                alignment: .trailing
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Aperçu")
                            Spacer()
                            Button("Régénérer") {
                                regenSeed = Int.random(in: 1...Int.max)
                            }
                            .disabled(isSaving || planningTeams.count < 2)
                        }
                    }
                }
            }
            .navigationTitle("Modifier le planning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                        .disabled(isSaving || isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isSubmitting = true
                        Task {
                            let didSave = await onSave(planningData)
                            if didSave {
                                await MainActor.run {
                                    isPresented = false
                                }
                            } else {
                                await MainActor.run {
                                    isSubmitting = false
                                }
                            }
                        }
                    } label: {
                        if isSaving || isSubmitting {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                        }
                    }
                    .disabled(isSaving || isSubmitting || planningTeams.count < 2 || generatedSlots.isEmpty)
                }
            }
            .onChange(of: isSaving) { oldValue, newValue in
                if oldValue == true, newValue == false {
                    isSubmitting = false
                }
            }
    }
    }

    private var planningTeams: [PlanningTeam] {
        let palette = ["#2563EB", "#DC2626", "#16A34A", "#D97706", "#7C3AED", "#0891B2", "#DB2777", "#4F46E5"]
        return teamNames.enumerated().map { index, label in
            PlanningTeam(label: label, color: palette[index % palette.count])
        }
    }

    private var generatedSlots: [PlanningSlot] {
        guard let startMinutes = parseTime(Self.timeString(from: startTime)) else { return [] }
        let scheduledGames = buildScheduledGames(from: planningTeams.map(\.label))
        guard !scheduledGames.isEmpty else { return [] }

        var slots: [PlanningSlot] = []
        var current = startMinutes

        for slotGamesRaw in scheduledGames {
            let slotGames = slotGamesRaw.enumerated().map { offset, game in
                PlanningGame(pitch: offset + 1, a: game.0, b: game.1)
            }
            slots.append(PlanningSlot(time: formatTime(current), games: slotGames))
            current += matchMin + breakMin
        }

        return slots
    }

    private var planningData: PlanningData {
        PlanningData(
            start: Self.timeString(from: startTime),
            pitches: pitches,
            matchMin: matchMin,
            breakMin: breakMin,
            forbidIntraClub: !allowsIntraClubMatches,
            matchesPerTeam: matchesPerTeam,
            restEveryX: maxConsecutiveMatches,
            allowRematches: allowRematches,
            regenSeed: regenSeed,
            teams: planningTeams,
            slots: generatedSlots
        )
    }

    private func buildScheduledGames(from labels: [String]) -> [[(String, String)]] {
        let teams = labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard teams.count > 1, pitches > 0 else { return [] }

        let targetMatches = max(matchesPerTeam, 1)
        let maxConsecutive = max(maxConsecutiveMatches, 1)

        var basePairs: [(String, String)] = []
        for i in 0..<teams.count {
            for j in (i + 1)..<teams.count {
                let lhs = teams[i]
                let rhs = teams[j]
                guard allowsIntraClubMatches || teamGroupKey(for: lhs) != teamGroupKey(for: rhs) else { continue }
                basePairs.append((lhs, rhs))
            }
        }

        guard !basePairs.isEmpty else { return [] }

        var generator = SeededGenerator(state: UInt64(max(regenSeed, 1)))
        basePairs.shuffle(using: &generator)
        let pairOrder = Dictionary(uniqueKeysWithValues: basePairs.enumerated().map { (index, pair) in
            (pairKey(for: pair.0, pair.1), index)
        })

        var matchesByTeam = Dictionary(uniqueKeysWithValues: teams.map { ($0, 0) })
        var consecutiveByTeam = Dictionary(uniqueKeysWithValues: teams.map { ($0, 0) })
        var playedPreviousSlot = Set<String>()
        var pairCounts: [String: Int] = [:]
        var slots: [[(String, String)]] = []

        while matchesByTeam.values.contains(where: { $0 < targetMatches }) {
            var usedThisSlot = Set<String>()
            var slot: [(String, String)] = []

            let availablePairs = basePairs
                .filter { lhs, rhs in
                    guard !usedThisSlot.contains(lhs), !usedThisSlot.contains(rhs) else { return false }
                    guard (matchesByTeam[lhs] ?? 0) < targetMatches, (matchesByTeam[rhs] ?? 0) < targetMatches else { return false }

                    if playedPreviousSlot.contains(lhs), (consecutiveByTeam[lhs] ?? 0) >= maxConsecutive {
                        return false
                    }
                    if playedPreviousSlot.contains(rhs), (consecutiveByTeam[rhs] ?? 0) >= maxConsecutive {
                        return false
                    }

                    let key = pairKey(for: lhs, rhs)
                    if !allowRematches, (pairCounts[key] ?? 0) > 0 {
                        return false
                    }

                    return true
                }
                .sorted { lhs, rhs in
                    let lhsNeed = (targetMatches - (matchesByTeam[lhs.0] ?? 0)) + (targetMatches - (matchesByTeam[lhs.1] ?? 0))
                    let rhsNeed = (targetMatches - (matchesByTeam[rhs.0] ?? 0)) + (targetMatches - (matchesByTeam[rhs.1] ?? 0))
                    if lhsNeed != rhsNeed { return lhsNeed > rhsNeed }

                    let lhsPairCount = pairCounts[pairKey(for: lhs.0, lhs.1)] ?? 0
                    let rhsPairCount = pairCounts[pairKey(for: rhs.0, rhs.1)] ?? 0
                    if lhsPairCount != rhsPairCount { return lhsPairCount < rhsPairCount }

                    return (pairOrder[pairKey(for: lhs.0, lhs.1)] ?? 0) < (pairOrder[pairKey(for: rhs.0, rhs.1)] ?? 0)
                }

            for pair in availablePairs {
                guard slot.count < pitches else { break }
                guard !usedThisSlot.contains(pair.0), !usedThisSlot.contains(pair.1) else { continue }
                slot.append(pair)
                usedThisSlot.insert(pair.0)
                usedThisSlot.insert(pair.1)
            }

            if slot.isEmpty {
                break
            }

            slots.append(slot)

            let playedThisSlot = Set(slot.flatMap { [$0.0, $0.1] })
            for team in teams {
                if playedThisSlot.contains(team) {
                    matchesByTeam[team, default: 0] += 1
                    consecutiveByTeam[team, default: 0] = playedPreviousSlot.contains(team)
                        ? (consecutiveByTeam[team, default: 0] + 1)
                        : 1
                } else {
                    consecutiveByTeam[team] = 0
                }
            }

            for pair in slot {
                pairCounts[pairKey(for: pair.0, pair.1), default: 0] += 1
            }
            playedPreviousSlot = playedThisSlot
        }

        return slots
    }

    private func teamGroupKey(for label: String) -> String {
        let normalized = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let strippedDigits = normalized.replacingOccurrences(
            of: "\\s*[0-9]+[a-z]?$",
            with: "",
            options: .regularExpression
        )
        return strippedDigits.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pairKey(for lhs: String, _ rhs: String) -> String {
        [lhs, rhs].sorted().joined(separator: "||")
    }

    private func parseTime(_ value: String) -> Int? {
        let components = value.split(separator: ":")
        guard components.count == 2,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              (0...23).contains(hours),
              (0...59).contains(minutes) else {
            return nil
        }
        return hours * 60 + minutes
    }

    private func formatTime(_ totalMinutes: Int) -> String {
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    private var trimmedNewTeamName: String {
        newTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addTeam() {
        let teamName = trimmedNewTeamName
        guard !teamName.isEmpty else { return }
        teamNames.append(teamName)
        newTeamName = ""
    }

    private func removeTeam(at index: Int) {
        guard teamNames.indices.contains(index) else { return }
        teamNames.remove(at: index)
    }

    private func teamColor(for label: String) -> Color {
        planningTeams.first(where: { $0.label == label }).flatMap { Color(hex: $0.color) } ?? .secondary
    }

    private static func time(from value: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: value) ?? Date()
    }

    private static func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = 2862933555777941757 &* state &+ 3037000493
        return state
    }
}

private struct MatchdayPlayersCard: View {
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

private struct MatchdayShareSheet: View {
    @Environment(\.dismiss) private var dismiss

    let urlString: String

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let image = qrImage {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240, maxHeight: 240)
                        .padding(20)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Lien public")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(urlString)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                HStack(spacing: 12) {
                    Button("Copier l'URL") {
                        UIPasteboard.general.string = urlString
                    }
                    .buttonStyle(.bordered)

                    if let url = URL(string: urlString) {
                        ShareLink(item: url) {
                            Label("Partager", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Partager le plateau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var qrImage: UIImage? {
        filter.setValue(Data(urlString.utf8), forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct EditMatchdayScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss

    let matchday: Matchday
    let isSaving: Bool
    let onSave: (String, String, String) -> Void

    @State private var address: String
    @State private var startTime: Date
    @State private var meetingTime: Date
    @State private var isSubmitting = false

    init(matchday: Matchday, isSaving: Bool, onSave: @escaping (String, String, String) -> Void) {
        self.matchday = matchday
        self.isSaving = isSaving
        self.onSave = onSave
        _address = State(initialValue: matchday.address ?? matchday.lieu ?? "")
        _startTime = State(initialValue: Self.time(from: matchday.startTime))
        _meetingTime = State(initialValue: Self.time(from: matchday.meetingTime))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Adresse") {
                    TextField("Adresse", text: $address, axis: .vertical)
                }

                Section("Horaires") {
                    DatePicker("Heure de début", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Heure de rendez-vous", selection: $meetingTime, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("Modifier")
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
                        isSubmitting = true
                        onSave(
                            address.trimmingCharacters(in: .whitespacesAndNewlines),
                            Self.timeString(from: startTime),
                            Self.timeString(from: meetingTime)
                        )
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
            .onChange(of: isSaving) { oldValue, newValue in
                if oldValue == true, newValue == false {
                    isSubmitting = false
                }
            }
        }
    }

    private static func time(from value: String?) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm"
        if let value, let parsed = formatter.date(from: value) {
            return parsed
        }
        return .now
    }

    private static func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct PendingScheduleSaveRequest: Identifiable {
    let id = UUID()
    let address: String
    let startTime: String
    let meetingTime: String
}

private struct MatchdayAttendanceSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let players: [Player]
    @Binding var selectedPlayerIDs: Set<String>
    let isSaving: Bool
    let onSave: () async -> String?

    @State private var sheetErrorMessage: String?
    @State private var isSubmitting = false
    @State private var searchText = ""

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
}

private struct AddressMapPreview: View {
    let address: String?

    @State private var position: MapCameraPosition = .automatic
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var isResolving = false

    var body: some View {
        ZStack {
            if let coordinate {
                Map(position: $position) {
                    Marker(address ?? "Lieu", coordinate: coordinate)
                }
                .mapStyle(.standard)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "map")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(address == nil ? "Adresse à définir" : "Carte indisponible")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
            }

            if isResolving {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: address) {
            await resolveAddress()
        }
    }

    private func resolveAddress() async {
        guard let address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            coordinate = nil
            return
        }

        isResolving = true
        defer { isResolving = false }

        do {
            guard let request = MKGeocodingRequest(addressString: address) else {
                coordinate = nil
                return
            }
            let mapItems = try await geocode(request: request)
            guard let location = mapItems.first?.location.coordinate else {
                coordinate = nil
                return
            }
            coordinate = location
            position = .region(
                MKCoordinateRegion(
                    center: location,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        } catch {
            coordinate = nil
        }
    }

    private func geocode(request: MKGeocodingRequest) async throws -> [MKMapItem] {
        try await withCheckedThrowingContinuation { continuation in
            request.getMapItems { items, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: items ?? [])
                }
            }
        }
    }
}

private struct ScheduleValueRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.weight(.medium))
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

private struct PlayerAvatar: View {
    let player: Player?
    let size: CGFloat

    private static let palette: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .pink
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

private struct DetailCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

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
    }
}
private extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        if cleaned.count == 8 {
            red = Double((value & 0xFF000000) >> 24) / 255
            green = Double((value & 0x00FF0000) >> 16) / 255
            blue = Double((value & 0x0000FF00) >> 8) / 255
            alpha = Double(value & 0x000000FF) / 255
        } else {
            red = Double((value & 0xFF0000) >> 16) / 255
            green = Double((value & 0x00FF00) >> 8) / 255
            blue = Double(value & 0x0000FF) / 255
            alpha = 1
        }

        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
