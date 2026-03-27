import Combine
import SwiftUI

@MainActor
final class MatchdayDetailViewModel: ObservableObject {
    @Published private(set) var matchday: Matchday
    @Published private(set) var players: [Player] = []
    @Published private(set) var attendance: [AttendanceRow] = []
    @Published private(set) var matches: [MatchLite] = []
    @Published private(set) var publicShareURL: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isUpdatingAttendance = false
    @Published private(set) var isSavingInfo = false
    @Published private(set) var isSharing = false
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
            async let playersTask = api.players()
            async let attendanceTask = api.attendanceBySession(type: "PLATEAU", sessionID: matchday.id)
            async let matchesTask = api.matches(matchdayID: matchday.id)

            players = try await playersTask.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            attendance = try await attendanceTask
            matches = try await matchesTask
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

    func saveInfo(address: String, startTime: String, meetingTime: String) async {
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
        } catch {
            errorMessage = error.localizedDescription
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
}

struct MatchdayDetailView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var teamScopeStore: TeamScopeStore

    @StateObject private var viewModel: MatchdayDetailViewModel
    @State private var isEditInfoPresented = false

    init(matchday: Matchday) {
        _viewModel = StateObject(wrappedValue: MatchdayDetailViewModel(matchday: matchday))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MatchdayInfoCard(
                    matchday: viewModel.matchday,
                    writable: writable
                ) {
                    isEditInfoPresented = true
                }

                MatchdayMatchesCard(
                    matches: viewModel.matches,
                    playerNamesByID: Dictionary(uniqueKeysWithValues: viewModel.players.map { ($0.id, $0.name) })
                )

                MatchdayAttendanceCard(
                    players: filteredPlayers,
                    attendanceByPlayerID: attendanceByPlayerID,
                    writable: writable,
                    isUpdating: viewModel.isUpdatingAttendance
                ) { playerID, present in
                    Task {
                        await viewModel.setAttendance(playerID: playerID, present: present)
                    }
                }

                MatchdayShareCard(
                    publicShareURL: viewModel.publicShareURL,
                    isSharing: viewModel.isSharing
                ) {
                    Task {
                        await viewModel.share()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Chargement")
            }
        }
        .navigationTitle("Plateau")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .sheet(isPresented: $isEditInfoPresented) {
            EditMatchdayInfoSheet(matchday: viewModel.matchday, isSaving: viewModel.isSavingInfo) { address, startTime, meetingTime in
                await viewModel.saveInfo(address: address, startTime: startTime, meetingTime: meetingTime)
                isEditInfoPresented = false
            }
            .presentationDetents([.medium, .large])
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
}

private struct MatchdayInfoCard: View {
    let matchday: Matchday
    let writable: Bool
    let onEdit: () -> Void

    var body: some View {
        DetailCard(title: "Informations") {
            LabeledContent("Date", value: DateFormatters.display(matchday.date))
            LabeledContent("Lieu", value: matchday.lieu ?? "À définir")
            LabeledContent("Adresse", value: matchday.address ?? "À définir")
            LabeledContent("Début", value: matchday.startTime ?? "À définir")
            LabeledContent("Rendez-vous", value: matchday.meetingTime ?? "À définir")

            if writable {
                Button("Modifier les informations") {
                    onEdit()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct MatchdayMatchesCard: View {
    let matches: [MatchLite]
    let playerNamesByID: [String: String]

    var body: some View {
        DetailCard(title: "Matchs") {
            if matches.isEmpty {
                Text("Aucun match pour ce plateau.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(matches) { match in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(matchTitle(for: match))
                                .font(.body.weight(.medium))
                            Spacer()
                            Text(scoreLabel(for: match))
                                .font(.subheadline.weight(.semibold))
                        }

                        Text(statusLabel(for: match))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !scorerNames(for: match).isEmpty {
                            Text("Buteurs: \(scorerNames(for: match).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func matchTitle(for match: MatchLite) -> String {
        if let opponentName = match.opponentName, !opponentName.isEmpty {
            return "\(match.type) • \(opponentName)"
        }
        return match.type
    }

    private func scoreLabel(for match: MatchLite) -> String {
        let home = match.teams.first(where: { $0.side == "home" })?.score ?? 0
        let away = match.teams.first(where: { $0.side == "away" })?.score ?? 0
        if match.played == false {
            return "À jouer"
        }
        return "\(home) - \(away)"
    }

    private func statusLabel(for match: MatchLite) -> String {
        if let status = match.status, !status.isEmpty {
            return "Statut: \(status)"
        }
        return "Statut: INCONNU"
    }

    private func scorerNames(for match: MatchLite) -> [String] {
        match.scorers.compactMap { scorer in
            scorer.playerName ?? playerNamesByID[scorer.playerId]
        }
    }
}

private struct MatchdayAttendanceCard: View {
    let players: [Player]
    let attendanceByPlayerID: [String: Bool]
    let writable: Bool
    let isUpdating: Bool
    let onToggle: (String, Bool) -> Void

    var body: some View {
        DetailCard(title: "Présences") {
            if players.isEmpty {
                Text("Aucun joueur disponible.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(players) { player in
                    Toggle(isOn: Binding(
                        get: { attendanceByPlayerID[player.id] ?? false },
                        set: { newValue in onToggle(player.id, newValue) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                            if let position = player.primaryPosition, !position.isEmpty {
                                Text(position)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!writable || isUpdating)
                }
            }
        }
    }

    private var summaryText: String {
        let presentCount = players.filter { attendanceByPlayerID[$0.id] == true }.count
        return "\(presentCount) présent(s) sur \(players.count)"
    }
}

private struct MatchdayShareCard: View {
    let publicShareURL: String?
    let isSharing: Bool
    let onShare: () -> Void

    var body: some View {
        DetailCard(title: "Partage public") {
            Button(publicShareURL == nil ? "Générer un lien public" : "Régénérer le lien public") {
                onShare()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSharing)

            if let publicShareURL, let shareURL = URL(string: publicShareURL) {
                ShareLink(item: shareURL) {
                    Label("Partager", systemImage: "square.and.arrow.up")
                }

                Text(publicShareURL)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct EditMatchdayInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    let matchday: Matchday
    let isSaving: Bool
    let onSave: (String, String, String) async -> Void

    @State private var address: String
    @State private var startTime: String
    @State private var meetingTime: String

    init(matchday: Matchday, isSaving: Bool, onSave: @escaping (String, String, String) async -> Void) {
        self.matchday = matchday
        self.isSaving = isSaving
        self.onSave = onSave
        _address = State(initialValue: matchday.address ?? "")
        _startTime = State(initialValue: matchday.startTime ?? "")
        _meetingTime = State(initialValue: matchday.meetingTime ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Adresse") {
                    TextField("Adresse", text: $address, axis: .vertical)
                }

                Section("Horaires") {
                    TextField("Heure de début", text: $startTime)
                    TextField("Heure de rendez-vous", text: $meetingTime)
                }
            }
            .navigationTitle("Informations du plateau")
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
                            await onSave(
                                address.trimmingCharacters(in: .whitespacesAndNewlines),
                                startTime.trimmingCharacters(in: .whitespacesAndNewlines),
                                meetingTime.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}
