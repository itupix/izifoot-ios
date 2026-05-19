import Combine
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

@MainActor
final class ClubHomeViewModel: ObservableObject {
    @Published private(set) var club: Club?
    @Published private(set) var teams: [Team] = []
    @Published private(set) var coaches: [Coach] = []
    @Published private(set) var isLoading = false
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

                Section("Equipes") {
                    Button("Ajouter une équipe") {
                        isCreateTeamSheetPresented = true
                    }

                    ForEach(viewModel.teams) { team in
                        let teamCoaches = viewModel.coaches(for: team.id)
                        let assignableCoaches = viewModel.assignableCoaches(for: team.id)

                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(team.name)
                                    .font(.headline)
                                Text([team.category, team.format].compactMap { $0 }.joined(separator: " • "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Coachs associés")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(teamCoaches.count)")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundStyle(.blue)
                                        .clipShape(Capsule())
                                }

                                if teamCoaches.isEmpty {
                                    Text("Aucun coach affecté à cette équipe.")
                                        .font(.footnote)
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
                                                Task { await viewModel.removeCoach(coach, from: team.id) }
                                            }
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.red)
                                            .disabled(viewModel.mutatingCoachIDs.contains(coach.id))
                                        }
                                    }
                                }

                                if !assignableCoaches.isEmpty {
                                    Menu("Affecter un coach") {
                                        ForEach(assignableCoaches) { coach in
                                            Button(coach.displayName) {
                                                Task { await viewModel.assignCoach(coach, to: team.id) }
                                            }
                                        }
                                    }
                                    .font(.footnote.weight(.semibold))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Coachs") {
                    Button("Ajouter un coach") {
                        isAddCoachSheetPresented = true
                    }

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
    @State private var category = ""
    @State private var format = ""

    let onSubmit: (String, String?, String?) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: $name)
                TextField("Catégorie", text: $category)
                TextField("Format (5v5, 8v8, 11v11)", text: $format)
            }
            .navigationTitle("Nouvelle équipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        Task {
                            await onSubmit(
                                name,
                                category.isEmpty ? nil : category,
                                format.isEmpty ? nil : format
                            )
                        }
                    }
                    .disabled(name.isEmpty)
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
