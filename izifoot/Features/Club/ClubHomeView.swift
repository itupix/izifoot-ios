import Combine
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

private struct TeamAgeCategoryOption: Identifiable {
    let value: String
    let label: String

    var id: String { value }
}

private let teamAgeCategoryOptions: [TeamAgeCategoryOption] = [
    TeamAgeCategoryOption(value: "U6", label: "U6"),
    TeamAgeCategoryOption(value: "U7", label: "U7"),
    TeamAgeCategoryOption(value: "U8", label: "U8"),
    TeamAgeCategoryOption(value: "U9", label: "U9"),
    TeamAgeCategoryOption(value: "U10", label: "U10"),
    TeamAgeCategoryOption(value: "U11", label: "U11"),
    TeamAgeCategoryOption(value: "U12", label: "U12"),
    TeamAgeCategoryOption(value: "U13", label: "U13"),
    TeamAgeCategoryOption(value: "U14", label: "U14"),
    TeamAgeCategoryOption(value: "U15", label: "U15"),
    TeamAgeCategoryOption(value: "U16", label: "U16"),
    TeamAgeCategoryOption(value: "U17", label: "U17"),
    TeamAgeCategoryOption(value: "U18", label: "U18"),
    TeamAgeCategoryOption(value: "U19", label: "U19"),
    TeamAgeCategoryOption(value: "U20", label: "U20"),
    TeamAgeCategoryOption(value: "SENIORS", label: "Seniors"),
    TeamAgeCategoryOption(value: "VETERANS", label: "Vétérans"),
]

private let teamAgeCategoryIndexByValue = Dictionary(uniqueKeysWithValues: teamAgeCategoryOptions.enumerated().map { ($0.element.value, $0.offset) })
private let teamAgeCategoryLabelByValue = Dictionary(uniqueKeysWithValues: teamAgeCategoryOptions.map { ($0.value, $0.label) })
private let teamGameFormatOptions = ["3v3", "5v5", "8v8", "11v11"]

private func normalizeCategoryToken(_ value: String) -> String {
    value
        .folding(options: .diacriticInsensitive, locale: .current)
        .uppercased()
        .replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
}

private func parseAgeCategorySelection(_ rawValue: String?) -> [String] {
    guard let rawValue else { return [] }

    var normalizedOptions = Dictionary(uniqueKeysWithValues: teamAgeCategoryOptions.map { (normalizeCategoryToken($0.label), $0.value) })
    teamAgeCategoryOptions.forEach { option in
        normalizedOptions[normalizeCategoryToken(option.value)] = option.value
    }

    let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return [] }

    let rangeParts = normalized
        .split(separator: "-")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    if rangeParts.count == 2 {
        guard
            let startValue = normalizedOptions[normalizeCategoryToken(rangeParts[0])],
            let endValue = normalizedOptions[normalizeCategoryToken(rangeParts[1])],
            let startIndex = teamAgeCategoryIndexByValue[startValue],
            let endIndex = teamAgeCategoryIndexByValue[endValue],
            startIndex <= endIndex
        else {
            return []
        }

        return teamAgeCategoryOptions[startIndex...endIndex].map(\.value)
    }

    guard let singleValue = normalizedOptions[normalizeCategoryToken(normalized)] else {
        return []
    }

    return [singleValue]
}

private func buildAgeCategoryLabel(_ values: [String]) -> String {
    let sorted = sortAgeCategories(values)

    guard let first = sorted.first else { return "" }
    let firstLabel = teamAgeCategoryLabelByValue[first] ?? first
    guard let last = sorted.last, sorted.count > 1 else { return firstLabel }
    let lastLabel = teamAgeCategoryLabelByValue[last] ?? last
    return "\(firstLabel)-\(lastLabel)"
}

private func suggestGameFormat(from values: [String]) -> String {
    let sorted = sortAgeCategories(values)

    guard let first = sorted.first else { return "" }
    if first == "SENIORS" || first == "VETERANS" {
        return "11v11"
    }

    let ageValue = first.replacingOccurrences(of: "U", with: "")
    guard let age = Int(ageValue) else { return "11v11" }
    if age <= 7 { return "3v3" }
    if age <= 9 { return "5v5" }
    if age <= 13 { return "8v8" }
    return "11v11"
}

private func normalizeGameFormat(_ value: String?) -> String {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return teamGameFormatOptions.contains(normalized) ? normalized : ""
}

private func sortAgeCategories(_ values: [String]) -> [String] {
    values.sorted {
        (teamAgeCategoryIndexByValue[$0] ?? .max) < (teamAgeCategoryIndexByValue[$1] ?? .max)
    }
}

private func areAgeCategoriesContiguous(_ values: [String]) -> Bool {
    let sorted = sortAgeCategories(values)
    guard !sorted.isEmpty else { return false }

    for index in 1..<sorted.count {
        let previous = teamAgeCategoryIndexByValue[sorted[index - 1]]
        let current = teamAgeCategoryIndexByValue[sorted[index]]
        if previous == nil || current == nil || current != previous! + 1 {
            return false
        }
    }

    return true
}

@MainActor
final class ClubHomeViewModel: ObservableObject {
    @Published private(set) var club: Club?
    @Published private(set) var teams: [Team] = []
    @Published private(set) var coaches: [Coach] = []
    @Published private(set) var isLoading = false
    @Published private(set) var mutatingTeamIDs = Set<String>()
    @Published private(set) var mutatingCoachIDs = Set<String>()
    @Published private(set) var isSavingCoach = false
    @Published private(set) var inviteURL: URL?
    @Published private(set) var inviteTargetName: String?
    @Published var isInviteSheetPresented = false
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI = IzifootAPI()) {
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let clubTask = api.myClub()
            async let teamsTask = api.teams()
            async let coachesTask = api.clubCoaches()
            club = try await clubTask
            let fetchedTeams = try await teamsTask
            let fetchedCoaches = try await coachesTask
            teams = fetchedTeams.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            coaches = fetchedCoaches.sorted(by: {
                "\($0.lastName ?? "") \($0.firstName ?? "") \($0.email ?? "")"
                    .localizedCaseInsensitiveCompare("\($1.lastName ?? "") \($1.firstName ?? "") \($1.email ?? "")") == .orderedAscending
            })
            errorMessage = nil
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func createTeam(name: String, category: String?, format: String?) async {
        do {
            _ = try await api.createTeam(name: name, category: category, format: format)
            await load()
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    @discardableResult
    func updateTeam(id: String, name: String, category: String, format: String) async -> Team? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFormat = format.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Le nom de l'équipe est requis."
            return nil
        }
        guard trimmedName.count <= 80 else {
            errorMessage = "Le nom de l'équipe doit contenir au maximum 80 caractères."
            return nil
        }
        guard !trimmedCategory.isEmpty else {
            errorMessage = "La catégorie est requise."
            return nil
        }
        guard !trimmedFormat.isEmpty else {
            errorMessage = "Le format est requis."
            return nil
        }

        mutatingTeamIDs.insert(id)
        defer { mutatingTeamIDs.remove(id) }

        do {
            let updatedTeam = try await api.updateTeam(
                id: id,
                name: trimmedName,
                category: trimmedCategory,
                format: trimmedFormat
            )
            await load()
            return updatedTeam
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
            return nil
        }
    }

    @discardableResult
    func deleteTeam(id: String) async -> Bool {
        mutatingTeamIDs.insert(id)
        defer { mutatingTeamIDs.remove(id) }

        do {
            try await api.deleteTeam(id: id)
            await load()
            return true
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
            return false
        }
    }

    func createCoach(firstName: String, lastName: String, email: String, phone: String?, teamID: String) async -> Bool {
        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedFirstName.isEmpty, !trimmedLastName.isEmpty, !trimmedEmail.isEmpty, !teamID.isEmpty else {
            errorMessage = "Merci de renseigner prénom, nom, email et équipe."
            return false
        }

        isSavingCoach = true
        defer { isSavingCoach = false }

        do {
            let response = try await api.createCoach(
                firstName: trimmedFirstName,
                lastName: trimmedLastName,
                email: trimmedEmail,
                phone: trimmedPhone?.isEmpty == true ? nil : trimmedPhone,
                teamID: teamID
            )
            await load()
            presentInviteIfAvailable(
                response.inviteUrl,
                coachName: [trimmedFirstName, trimmedLastName].filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            )
            return true
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
            return false
        }
    }

    @discardableResult
    func renameClub(name: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.count >= 2, trimmedName.count <= 120 else {
            errorMessage = "Le nom du club doit contenir entre 2 et 120 caractères."
            return false
        }

        do {
            let updatedClub = try await api.renameClub(name: trimmedName)
            club = updatedClub
            return true
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
            return false
        }
    }

    func coaches(for teamID: String) -> [Coach] {
        coaches.filter { $0.managedTeamIds.contains(teamID) }
    }

    func assignableCoaches(for teamID: String) -> [Coach] {
        coaches.filter { !$0.managedTeamIds.contains(teamID) }
    }

    func assignCoach(_ coach: Coach, to teamID: String) async {
        let nextManagedTeamIDs = Array(Set(coach.managedTeamIds + [teamID])).sorted()
        await updateCoachTeams(id: coach.id, managedTeamIDs: nextManagedTeamIDs)
    }

    func removeCoach(_ coach: Coach, from teamID: String) async {
        let nextManagedTeamIDs = coach.managedTeamIds.filter { $0 != teamID }
        await updateCoachTeams(id: coach.id, managedTeamIDs: nextManagedTeamIDs)
    }

    func deleteCoach(_ coach: Coach) async {
        mutatingCoachIDs.insert(coach.id)
        defer { mutatingCoachIDs.remove(coach.id) }
        do {
            try await api.deleteCoach(id: coach.id)
            await load()
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func inviteCoach(_ coach: Coach) async {
        mutatingCoachIDs.insert(coach.id)
        defer { mutatingCoachIDs.remove(coach.id) }

        do {
            let response = try await api.inviteCoach(id: coach.id)
            await load()
            presentInviteIfAvailable(response.inviteUrl, coachName: coach.displayName)
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    private func updateCoachTeams(id: String, managedTeamIDs: [String]) async {
        mutatingCoachIDs.insert(id)
        defer { mutatingCoachIDs.remove(id) }
        do {
            try await api.updateCoachTeams(id: id, managedTeamIDs: managedTeamIDs)
            await load()
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    private func presentInviteIfAvailable(_ inviteURLString: String?, coachName: String) {
        guard let inviteURLString,
              !inviteURLString.isEmpty,
              let url = URL(string: inviteURLString) else {
            return
        }

        inviteURL = url
        inviteTargetName = coachName.isEmpty ? "le coach" : coachName
        isInviteSheetPresented = true
    }
}

struct ClubHomeView: View {
    @StateObject private var viewModel = ClubHomeViewModel()
    @State private var isCreateTeamSheetPresented = false
    @State private var isRenameClubSheetPresented = false
    @State private var isAddCoachSheetPresented = false
    @State private var selectedTeamSheetTarget: TeamSheetTarget?
    @State private var coachPendingDelete: Coach?

    var body: some View {
        NavigationStack {
            List {
                if let club = viewModel.club {
                    Section("Club") {
                        Label(club.name, systemImage: "building.2.crop.circle")
                        Button("Renommer le club") {
                            isRenameClubSheetPresented = true
                        }
                    }
                }

                Section {
                    if viewModel.teams.isEmpty {
                        Text("Aucune équipe.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.teams) { team in
                            Button {
                                selectedTeamSheetTarget = TeamSheetTarget(id: team.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Text(team.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.mutatingTeamIDs.contains(team.id))
                        }
                    }
                } header: {
                    SectionActionHeader(title: "Equipes") {
                        isCreateTeamSheetPresented = true
                    }
                }

                Section {
                    if viewModel.coaches.isEmpty {
                        Text("Aucun coach.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.coaches) { coach in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(coach.displayName)
                                    .font(.headline)
                                if let email = coach.email, !email.isEmpty {
                                    Text(email)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Text(coach.managedTeamsLabel)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                if let status = coach.invitationStatusLabel {
                                    Text(status)
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                if coach.invitationStatus?.uppercased() != "ACCEPTED" {
                                    Button(viewModel.mutatingCoachIDs.contains(coach.id) ? "Envoi…" : coachInviteButtonTitle(for: coach)) {
                                        Task { await viewModel.inviteCoach(coach) }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(viewModel.mutatingCoachIDs.contains(coach.id))
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Supprimer", role: .destructive) {
                                    coachPendingDelete = coach
                                }
                            }
                        }
                    }
                } header: {
                    SectionActionHeader(title: "Coachs") {
                        isAddCoachSheetPresented = true
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Chargement")
                }
            }
            .navigationTitle("Mon club")
            .refreshable {
                await viewModel.load()
            }
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $isCreateTeamSheetPresented) {
                CreateTeamSheet { name, category, format in
                    await viewModel.createTeam(name: name, category: category, format: format)
                    isCreateTeamSheetPresented = false
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $isRenameClubSheetPresented) {
                if let club = viewModel.club {
                    RenameClubSheet(initialName: club.name) { nextName in
                        let success = await viewModel.renameClub(name: nextName)
                        if success {
                            isRenameClubSheetPresented = false
                        }
                    }
                    .presentationDetents([.fraction(0.3), .medium])
                }
            }
            .sheet(isPresented: $isAddCoachSheetPresented) {
                AddCoachSheet(teams: viewModel.teams, isSubmitting: viewModel.isSavingCoach) { firstName, lastName, email, phone, teamID in
                    let success = await viewModel.createCoach(
                        firstName: firstName,
                        lastName: lastName,
                        email: email,
                        phone: phone,
                        teamID: teamID
                    )
                    if success {
                        isAddCoachSheetPresented = false
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $viewModel.isInviteSheetPresented) {
                if let url = viewModel.inviteURL {
                    InviteCoachSheet(url: url, coachName: viewModel.inviteTargetName ?? "le coach")
                }
            }
            .sheet(item: $selectedTeamSheetTarget) { target in
                if let team = viewModel.teams.first(where: { $0.id == target.id }) {
                    TeamDetailsSheet(
                        team: team,
                        teamCoaches: viewModel.coaches(for: target.id),
                        assignableCoaches: viewModel.assignableCoaches(for: target.id),
                        mutatingCoachIDs: viewModel.mutatingCoachIDs,
                        isSubmitting: viewModel.mutatingTeamIDs.contains(target.id),
                        onSave: { name, category, format in
                            await viewModel.updateTeam(id: target.id, name: name, category: category, format: format)
                        },
                        onDelete: {
                            await viewModel.deleteTeam(id: target.id)
                        },
                        onAssignCoach: { coach in
                            await viewModel.assignCoach(coach, to: target.id)
                        },
                        onRemoveCoach: { coach in
                            await viewModel.removeCoach(coach, from: target.id)
                        }
                    )
                    .presentationDetents([.medium, .large])
                } else {
                    NavigationStack {
                        Text("Équipe introuvable.")
                            .foregroundStyle(.secondary)
                            .navigationTitle("Équipe")
                    }
                }
            }
            .confirmationDialog(
                "Supprimer ce coach du club ?",
                isPresented: Binding(
                    get: { coachPendingDelete != nil },
                    set: { if !$0 { coachPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    guard let coach = coachPendingDelete else { return }
                    Task {
                        await viewModel.deleteCoach(coach)
                        coachPendingDelete = nil
                    }
                }
                Button("Annuler", role: .cancel) {
                    coachPendingDelete = nil
                }
            } message: {
                if let coachPendingDelete {
                    Text(coachPendingDelete.displayName)
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
}

private func coachInviteButtonTitle(for coach: Coach) -> String {
    coach.invitationStatus?.uppercased() == "PENDING" ? "Renvoyer l'invitation" : "Inviter"
}

private struct TeamSheetTarget: Identifiable {
    let id: String
}

private struct SectionActionHeader: View {
    let title: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Spacer()
            Button("Ajouter") {
                action()
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .textCase(nil)
    }
}

private struct TeamFormFields: View {
    @Binding var name: String
    @Binding var selectedAgeCategories: [String]
    @Binding var teamGameFormat: String

    let isAgeSelectionContiguous: Bool
    let onToggleAgeCategory: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nom de l'équipe")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Nom de l'équipe", text: $name)
                .textInputAutocapitalization(.words)
        }
        .padding(.vertical, 4)

        VStack(alignment: .leading, spacing: 10) {
            Text("Catégorie d'âge")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(teamAgeCategoryOptions) { option in
                    let isSelected = selectedAgeCategories.contains(option.value)
                    Button(option.label) {
                        onToggleAgeCategory(option.value)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(isSelected ? Color.accentColor.opacity(0.16) : Color(uiColor: .secondarySystemFill))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }
            }

            if !isAgeSelectionContiguous && !selectedAgeCategories.isEmpty {
                Text("Les catégories sélectionnées doivent se suivre (ex: U8-U10).")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)

        VStack(alignment: .leading, spacing: 8) {
            Text("Format de jeu")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Format de jeu", selection: $teamGameFormat) {
                Text("Sélectionner un format").tag("")
                ForEach(teamGameFormatOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(.vertical, 4)
    }
}

private struct TeamDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let team: Team
    let teamCoaches: [Coach]
    let assignableCoaches: [Coach]
    let mutatingCoachIDs: Set<String>
    let isSubmitting: Bool
    let onSave: (String, String, String) async -> Team?
    let onDelete: () async -> Bool
    let onAssignCoach: (Coach) async -> Void
    let onRemoveCoach: (Coach) async -> Void

    @State private var name: String
    @State private var selectedAgeCategories: [String]
    @State private var teamGameFormat: String
    @State private var isDeleteConfirmationPresented = false

    init(
        team: Team,
        teamCoaches: [Coach],
        assignableCoaches: [Coach],
        mutatingCoachIDs: Set<String>,
        isSubmitting: Bool,
        onSave: @escaping (String, String, String) async -> Team?,
        onDelete: @escaping () async -> Bool,
        onAssignCoach: @escaping (Coach) async -> Void,
        onRemoveCoach: @escaping (Coach) async -> Void
    ) {
        self.team = team
        self.teamCoaches = teamCoaches
        self.assignableCoaches = assignableCoaches
        self.mutatingCoachIDs = mutatingCoachIDs
        self.isSubmitting = isSubmitting
        self.onSave = onSave
        self.onDelete = onDelete
        self.onAssignCoach = onAssignCoach
        self.onRemoveCoach = onRemoveCoach
        _name = State(initialValue: team.name)
        let parsedCategories = parseAgeCategorySelection(team.category)
        _selectedAgeCategories = State(initialValue: parsedCategories)
        _teamGameFormat = State(initialValue: normalizeGameFormat(team.format).isEmpty ? suggestGameFormat(from: parsedCategories) : normalizeGameFormat(team.format))
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sortedSelectedAgeCategories: [String] {
        sortAgeCategories(selectedAgeCategories)
    }

    private var isAgeSelectionContiguous: Bool {
        areAgeCategoriesContiguous(selectedAgeCategories)
    }

    private var selectedAgeCategoryLabel: String {
        buildAgeCategoryLabel(sortedSelectedAgeCategories)
    }

    private var canSave: Bool {
        !isSubmitting && !trimmedName.isEmpty && trimmedName.count <= 80 && isAgeSelectionContiguous && !teamGameFormat.isEmpty
    }

    private var isCoachMutationInFlight: Bool {
        !mutatingCoachIDs.isEmpty
    }

    private func toggleAgeCategory(_ value: String) {
        if selectedAgeCategories.contains(value) {
            selectedAgeCategories.removeAll { $0 == value }
        } else {
            selectedAgeCategories.append(value)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Équipe") {
                    TeamFormFields(
                        name: $name,
                        selectedAgeCategories: $selectedAgeCategories,
                        teamGameFormat: $teamGameFormat,
                        isAgeSelectionContiguous: isAgeSelectionContiguous,
                        onToggleAgeCategory: toggleAgeCategory
                    )
                }

                Section("Coachs associés") {
                    if teamCoaches.isEmpty {
                        Text("Aucun coach affecté à cette équipe.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(teamCoaches) { coach in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(coach.displayName)
                                        .font(.subheadline.weight(.medium))
                                    if let status = coach.invitationStatusLabel {
                                        Text(status)
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                }

                                Spacer()

                                Button("Retirer") {
                                    Task { await onRemoveCoach(coach) }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                                .disabled(isSubmitting || mutatingCoachIDs.contains(coach.id))
                            }
                        }
                    }
                }

                Section {
                    if assignableCoaches.isEmpty {
                        Text("Tous les coachs du club sont déjà affectés à cette équipe.")
                            .foregroundStyle(.secondary)
                    } else {
                        Menu("Affecter un coach") {
                            ForEach(assignableCoaches) { coach in
                                Button(coach.displayName) {
                                    Task { await onAssignCoach(coach) }
                                }
                            }
                        }
                        .disabled(isSubmitting || isCoachMutationInFlight)
                    }
                }

                Section {
                    Button("Supprimer l'équipe", role: .destructive) {
                        isDeleteConfirmationPresented = true
                    }
                    .disabled(isSubmitting || isCoachMutationInFlight)
                }
            }
            .navigationTitle(trimmedName.isEmpty ? team.name : trimmedName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let updatedTeam = await onSave(trimmedName, selectedAgeCategoryLabel, teamGameFormat) {
                                name = updatedTeam.name
                                selectedAgeCategories = parseAgeCategorySelection(updatedTeam.category)
                                teamGameFormat = normalizeGameFormat(updatedTeam.format)
                            }
                        }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: sortedSelectedAgeCategories) { _, newValue in
                let suggestion = suggestGameFormat(from: newValue)
                if !suggestion.isEmpty {
                    teamGameFormat = suggestion
                }
            }
            .confirmationDialog(
                "Supprimer cette équipe ?",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    Task {
                        let deleted = await onDelete()
                        if deleted {
                            dismiss()
                        }
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Cette action est définitive et peut échouer si l'équipe est encore référencée ailleurs.")
            }
        }
    }
}

struct RenameClubSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isSubmitting = false

    let onSubmit: (String) async -> Void

    init(initialName: String, onSubmit: @escaping (String) async -> Void) {
        _name = State(initialValue: initialName)
        self.onSubmit = onSubmit
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidName: Bool {
        trimmedName.count >= 2 && trimmedName.count <= 120
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom du club", text: $name)
                    .textInputAutocapitalization(.words)
                Text("Entre 2 et 120 caractères.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Renommer le club")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Enregistrement..." : "Enregistrer") {
                        Task {
                            isSubmitting = true
                            await onSubmit(trimmedName)
                            isSubmitting = false
                        }
                    }
                    .disabled(isSubmitting || !isValidName)
                }
            }
        }
    }
}

struct CreateTeamSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedAgeCategories: [String] = []
    @State private var teamGameFormat = ""

    let onSubmit: (String, String?, String?) async -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sortedSelectedAgeCategories: [String] {
        sortAgeCategories(selectedAgeCategories)
    }

    private var isAgeSelectionContiguous: Bool {
        areAgeCategoriesContiguous(selectedAgeCategories)
    }

    private var selectedAgeCategoryLabel: String {
        buildAgeCategoryLabel(sortedSelectedAgeCategories)
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 80 && isAgeSelectionContiguous && !teamGameFormat.isEmpty
    }

    private func toggleAgeCategory(_ value: String) {
        if selectedAgeCategories.contains(value) {
            selectedAgeCategories.removeAll { $0 == value }
        } else {
            selectedAgeCategories.append(value)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Équipe") {
                    TeamFormFields(
                        name: $name,
                        selectedAgeCategories: $selectedAgeCategories,
                        teamGameFormat: $teamGameFormat,
                        isAgeSelectionContiguous: isAgeSelectionContiguous,
                        onToggleAgeCategory: toggleAgeCategory
                    )
                }
            }
            .navigationTitle("Nouvelle équipe")
            .onChange(of: sortedSelectedAgeCategories) { _, newValue in
                let suggestion = suggestGameFormat(from: newValue)
                if !suggestion.isEmpty {
                    teamGameFormat = suggestion
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await onSubmit(
                                trimmedName,
                                selectedAgeCategoryLabel.isEmpty ? nil : selectedAgeCategoryLabel,
                                teamGameFormat.isEmpty ? nil : teamGameFormat
                            )
                        }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }
}

struct AddCoachSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var teamID = ""

    let teams: [Team]
    let isSubmitting: Bool
    let onSubmit: (String, String, String, String?, String) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Prénom", text: $firstName)
                    .textInputAutocapitalization(.words)
                TextField("Nom", text: $lastName)
                    .textInputAutocapitalization(.words)
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                TextField("Téléphone", text: $phone)
                    .keyboardType(.phonePad)

                Picker("Équipe initiale", selection: $teamID) {
                    Text("Sélectionner une équipe").tag("")
                    ForEach(teams) { team in
                        Text(team.name).tag(team.id)
                    }
                }
            }
            .navigationTitle("Ajouter un coach")
            .task {
                if teamID.isEmpty {
                    teamID = teams.first?.id ?? ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Ajout..." : "Ajouter") {
                        Task {
                            await onSubmit(
                                firstName,
                                lastName,
                                email,
                                phone.isEmpty ? nil : phone,
                                teamID
                            )
                        }
                    }
                    .disabled(
                        isSubmitting
                            || firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || teamID.isEmpty
                    )
                }
            }
        }
    }
}

private struct InviteCoachSheet: View {
    let url: URL
    let coachName: String

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Partagez ce QR code ou ce lien avec \(coachName) pour finaliser le compte.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if let image = qrImage {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                            )
                    }

                    Text(url.absoluteString)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )

                    ShareLink(item: url) {
                        Label("Partager le lien", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Invitation")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var qrImage: UIImage? {
        filter.message = Data(url.absoluteString.utf8)
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
