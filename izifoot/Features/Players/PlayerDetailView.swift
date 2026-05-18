import Combine
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

private let defaultPlayerPrimaryPosition = "NON DEFINI"

fileprivate enum PlayerInvitationStatusValue: String {
    case none = "NONE"
    case pending = "PENDING"
    case accepted = "ACCEPTED"

    static func fromAPI(_ raw: String?) -> PlayerInvitationStatusValue {
        guard let raw else { return .none }
        return PlayerInvitationStatusValue(rawValue: raw.uppercased()) ?? .none
    }
}

@MainActor
final class PlayerDetailViewModel: ObservableObject {
    @Published private(set) var player: Player?
    @Published private(set) var isLoading = false
    @Published private(set) var isInviting = false
    @Published private(set) var isSavingProfile = false
    @Published private(set) var isSavingInvitePrerequisites = false
    @Published private(set) var deletingParentID: String?
    @Published fileprivate var invitationStatus: PlayerInvitationStatusValue = .none
    @Published private(set) var inviteURL: URL?
    @Published var isInviteSheetPresented = false
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI = IzifootAPI()) {
        self.api = api
    }

    private func refreshInvitationStatus(id: String) async {
        do {
            let invitation = try await api.playerInvitationStatus(id: id)
            invitationStatus = .fromAPI(invitation.status)
        } catch {
            invitationStatus = .none
        }
    }

    func load(id: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            player = try await api.player(id: id)
            await refreshInvitationStatus(id: id)
            errorMessage = nil
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func invitePlayer(id: String, email: String? = nil, phone: String? = nil) async {
        isInviting = true
        defer { isInviting = false }

        do {
            let response = try await api.invitePlayer(id: id, email: email, phone: phone)
            invitationStatus = .fromAPI(response.status)
            if let inviteUrl = response.inviteUrl, !inviteUrl.isEmpty, let url = URL(string: inviteUrl) {
                inviteURL = url
                isInviteSheetPresented = true
            } else {
                errorMessage = "Invitation envoyée mais lien indisponible."
            }
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func updatePlayer(
        id: String,
        firstName: String,
        lastName: String,
        email: String,
        phone: String,
        licence: String,
        primaryPosition: String,
        secondaryPosition: String,
        isChild: Bool
    ) async -> Bool {
        isSavingProfile = true
        defer { isSavingProfile = false }

        do {
            player = try await api.updatePlayer(
                id: id,
                firstName: firstName,
                lastName: lastName,
                email: email,
                phone: phone,
                licence: licence,
                primaryPosition: primaryPosition,
                secondaryPosition: secondaryPosition,
                isChild: isChild
            )
            await refreshInvitationStatus(id: id)
            NotificationCenter.default.post(name: .playerDidUpdate, object: nil, userInfo: ["playerId": id])
            errorMessage = nil
            return true
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
            return false
        }
    }

    func updateAdultInvitePrerequisites(id: String, lastName: String, email: String, phone: String) async -> Bool {
        isSavingInvitePrerequisites = true
        defer { isSavingInvitePrerequisites = false }

        do {
            player = try await api.updatePlayerInvitePrerequisites(id: id, lastName: lastName, email: email, phone: phone)
            await refreshInvitationStatus(id: id)
            NotificationCenter.default.post(name: .playerDidUpdate, object: nil, userInfo: ["playerId": id])
            errorMessage = nil
            return true
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
            return false
        }
    }

    func deleteParent(playerID: String, parentID: String) async -> Bool {
        deletingParentID = parentID
        defer { deletingParentID = nil }

        do {
            try await api.deletePlayerParent(playerID: playerID, parentID: parentID)
            await load(id: playerID)
            return true
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
            return false
        }
    }
}

struct PlayerDetailView: View {
    let playerID: String

    @StateObject private var viewModel = PlayerDetailViewModel()
    @State private var isEditSheetPresented = false
    @State private var isAdultInvitePrerequisitesSheetPresented = false
    @State private var isParentInviteSheetPresented = false
    @State private var parentInviteEmail = ""
    @State private var parentInvitePhone = ""
    @State private var parentToDelete: Player.ParentContact?
    @State private var editFirstName = ""
    @State private var editLastName = ""
    @State private var editEmail = ""
    @State private var editPhone = ""
    @State private var editLicence = ""
    @State private var editPrimaryPosition = ""
    @State private var editSecondaryPosition = ""
    @State private var editIsChild = false

    var body: some View {
        List {
            if let player = viewModel.player {
                Section("Identité") {
                    if let firstName = player.firstName {
                        LabeledContent("Prénom", value: firstName)
                    }
                    LabeledContent("Nom", value: displayValue(player.lastName))
                }

                Section("Sport") {
                    LabeledContent("Licence", value: displayValue(player.licence))
                    if let primaryPosition = player.primaryPosition {
                        LabeledContent("Poste principal", value: primaryPosition)
                    }
                    if let secondaryPosition = player.secondaryPosition {
                        LabeledContent("Poste secondaire", value: secondaryPosition)
                    }
                }

                if !player.isChild {
                    Section("Contact") {
                        LabeledContent("Email", value: displayValue(player.email))
                        LabeledContent("Téléphone", value: displayValue(player.phone))
                    }
                }

                if player.isChild {
                    Section("Parents") {
                        if player.parentContacts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Aucun parent lié")
                                    .foregroundStyle(.secondary)
                                Button("Ajouter un parent") {
                                    openParentInviteSheet()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            ForEach(Array(player.parentContacts.enumerated()), id: \.element.id) { index, parent in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Parent \(index + 1)")
                                            .font(.headline)
                                        Spacer()
                                        if let parentID = parent.parentId, !parentID.isEmpty {
                                            Button(role: .destructive) {
                                                parentToDelete = parent
                                            } label: {
                                                Text(viewModel.deletingParentID == parentID ? "Suppression…" : "Supprimer")
                                            }
                                            .disabled(viewModel.deletingParentID == parentID)
                                        }
                                    }
                                    LabeledContent("Prénom", value: displayValue(parent.firstName))
                                    LabeledContent("Nom", value: displayValue(parent.lastName))
                                    LabeledContent("Email", value: displayValue(parent.email))
                                    LabeledContent("Téléphone", value: displayValue(parent.phone))
                                }
                                .padding(.vertical, 4)
                            }
                            Button("Ajouter un autre parent") {
                                openParentInviteSheet()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section("Invitation compte") {
                    LabeledContent("Statut", value: invitationStatusLabel(viewModel.invitationStatus))
                    let blockingFields = adultInviteBlockingFields(player)
                    if !player.isChild, !blockingFields.isEmpty {
                        Text("Complétez \(formattedFieldList(blockingFields)) avant d’envoyer l’invitation.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if viewModel.invitationStatus != .accepted || player.isChild {
                        Button(viewModel.isInviting ? "Envoi…" : inviteButtonTitle(for: player)) {
                            if player.isChild {
                                openParentInviteSheet()
                            } else if !blockingFields.isEmpty {
                                isAdultInvitePrerequisitesSheetPresented = true
                            } else {
                                Task { await viewModel.invitePlayer(id: playerID) }
                            }
                        }
                        .disabled(viewModel.isInviting || viewModel.isSavingInvitePrerequisites || viewModel.isSavingProfile)
                    }
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Chargement")
            }
        }
        .navigationTitle("Joueur")
        .toolbar {
            if let player = viewModel.player {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Modifier") {
                        prepareEditSheet(for: player)
                    }
                    .disabled(viewModel.isSavingProfile || viewModel.isSavingInvitePrerequisites || viewModel.isInviting)
                }
            }
        }
        .task {
            await viewModel.load(id: playerID)
        }
        .sheet(isPresented: $isEditSheetPresented) {
            EditPlayerSheet(
                firstName: $editFirstName,
                lastName: $editLastName,
                email: $editEmail,
                phone: $editPhone,
                licence: $editLicence,
                primaryPosition: $editPrimaryPosition,
                secondaryPosition: $editSecondaryPosition,
                isChild: $editIsChild,
                isSaving: viewModel.isSavingProfile
            ) { payload in
                let saved = await viewModel.updatePlayer(
                    id: playerID,
                    firstName: payload.firstName,
                    lastName: payload.lastName,
                    email: payload.email,
                    phone: payload.phone,
                    licence: payload.licence,
                    primaryPosition: payload.primaryPosition.isEmpty ? defaultPlayerPrimaryPosition : payload.primaryPosition,
                    secondaryPosition: payload.secondaryPosition,
                    isChild: payload.isChild
                )
                if saved {
                    isEditSheetPresented = false
                }
                return saved
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $viewModel.isInviteSheetPresented) {
            if let url = viewModel.inviteURL {
                InvitePlayerSheet(url: url)
            }
        }
        .sheet(isPresented: $isAdultInvitePrerequisitesSheetPresented) {
            if let player = viewModel.player {
                CompleteAdultInviteInfoSheet(
                    player: player,
                    isSaving: viewModel.isSavingInvitePrerequisites
                ) { payload in
                    await viewModel.updateAdultInvitePrerequisites(
                        id: playerID,
                        lastName: payload.lastName,
                        email: payload.email,
                        phone: payload.phone
                    )
                }
            }
        }
        .sheet(isPresented: $isParentInviteSheetPresented) {
            NavigationStack {
                Form {
                    Section("Inviter un parent") {
                        TextField("Adresse e-mail du parent", text: $parentInviteEmail)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                        TextField("Téléphone du parent", text: $parentInvitePhone)
                            .keyboardType(.phonePad)
                        Text("Au moins un des deux champs est requis.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Inviter un parent")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Annuler") { isParentInviteSheetPresented = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Continuer") {
                            let email = parentInviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                            let phone = parentInvitePhone.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !email.isEmpty || !phone.isEmpty else {
                                viewModel.errorMessage = "Merci de renseigner au moins un e-mail ou un téléphone parent."
                                return
                            }
                            isParentInviteSheetPresented = false
                            Task {
                                await viewModel.invitePlayer(
                                    id: playerID,
                                    email: email.isEmpty ? nil : email,
                                    phone: phone.isEmpty ? nil : phone
                                )
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Supprimer ce parent de la fiche joueur ?",
            isPresented: Binding(
                get: { parentToDelete != nil },
                set: { if !$0 { parentToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer le parent", role: .destructive) {
                guard let parent = parentToDelete, let parentID = parent.parentId, !parentID.isEmpty else {
                    parentToDelete = nil
                    return
                }
                Task {
                    _ = await viewModel.deleteParent(playerID: playerID, parentID: parentID)
                    parentToDelete = nil
                }
            }
            Button("Annuler", role: .cancel) {
                parentToDelete = nil
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

    private func prepareEditSheet(for player: Player) {
        editFirstName = player.firstName ?? ""
        editLastName = player.lastName ?? ""
        editEmail = player.email ?? ""
        editPhone = player.phone ?? ""
        editLicence = player.licence ?? ""
        editPrimaryPosition = editablePrimaryPosition(player.primaryPosition)
        editSecondaryPosition = player.secondaryPosition ?? ""
        editIsChild = player.isChild
        isEditSheetPresented = true
    }

    private func editablePrimaryPosition(_ value: String?) -> String {
        guard let value else { return "" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased() != defaultPlayerPrimaryPosition else { return "" }
        return trimmed
    }

    private func invitationStatusLabel(_ status: PlayerInvitationStatusValue) -> String {
        switch status {
        case .none: return "Non invité"
        case .pending: return "Invitation en attente"
        case .accepted: return "Compte activé"
        }
    }

    private func openParentInviteSheet() {
        parentInviteEmail = ""
        parentInvitePhone = ""
        isParentInviteSheetPresented = true
    }

    private func inviteButtonTitle(for player: Player) -> String {
        if !player.isChild, !adultInviteBlockingFields(player).isEmpty {
            return "Compléter avant d'inviter"
        }
        if player.isChild {
            if viewModel.invitationStatus == .pending {
                return "Renvoyer l'invitation"
            }
            return player.parentContacts.isEmpty ? "Inviter un parent" : "Inviter un autre parent"
        }
        return viewModel.invitationStatus == .pending ? "Renvoyer l'invitation" : "Inviter"
    }

    private func adultInviteBlockingFields(_ player: Player) -> [String] {
        guard !player.isChild else { return [] }

        var fields: [String] = []
        if !hasValue(player.lastName) {
            fields.append("le nom")
        }
        if !hasValue(player.email) || !isValidEmail(player.email) {
            fields.append("un e-mail valide")
        }
        if !hasValue(player.phone) {
            fields.append("le téléphone")
        }
        return fields
    }

    private func formattedFieldList(_ fields: [String]) -> String {
        switch fields.count {
        case 0:
            return ""
        case 1:
            return fields[0]
        case 2:
            return "\(fields[0]) et \(fields[1])"
        default:
            let prefix = fields.dropLast().joined(separator: ", ")
            return "\(prefix) et \(fields.last ?? "")"
        }
    }

    private func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isValidEmail(_ value: String?) -> Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func displayValue(_ value: String?) -> String {
        guard hasValue(value) else { return "—" }
        guard let value else { return "—" }
        return value
    }
}

private struct EditPlayerPayload {
    let firstName: String
    let lastName: String
    let email: String
    let phone: String
    let licence: String
    let primaryPosition: String
    let secondaryPosition: String
    let isChild: Bool
}

private struct EditPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var email: String
    @Binding var phone: String
    @Binding var licence: String
    @Binding var primaryPosition: String
    @Binding var secondaryPosition: String
    @Binding var isChild: Bool

    let isSaving: Bool
    let onSubmit: (EditPlayerPayload) async -> Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Identité") {
                    TextField("Prénom", text: $firstName)
                        .textInputAutocapitalization(.words)
                    TextField("Nom", text: $lastName)
                        .textInputAutocapitalization(.words)
                    Toggle("Enfant", isOn: $isChild)
                }

                Section("Sport") {
                    TextField("Licence", text: $licence)
                        .textInputAutocapitalization(.characters)
                    TextField("Poste principal", text: $primaryPosition)
                        .textInputAutocapitalization(.words)
                    TextField("Poste secondaire", text: $secondaryPosition)
                        .textInputAutocapitalization(.words)
                }

                if !isChild {
                    Section("Contact") {
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                        TextField("Téléphone", text: $phone)
                            .keyboardType(.phonePad)
                    }

                    Section {
                        Text("Le nom, l’e-mail et le téléphone sont requis uniquement pour l’invitation du joueur adulte.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if !trimmedEmail.isEmpty, !isValidEmail(trimmedEmail) {
                            Text("Merci de saisir une adresse e-mail valide.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    Section {
                        Text("Pour un enfant, les coordonnées se gèrent via l’invitation d’un parent.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Modifier")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Enregistrement…" : "Enregistrer") {
                        Task {
                            let saved = await onSubmit(
                                EditPlayerPayload(
                                    firstName: trimmedFirstName,
                                    lastName: trimmedLastName,
                                    email: isChild ? "" : trimmedEmail,
                                    phone: isChild ? "" : trimmedPhone,
                                    licence: trimmedLicence,
                                    primaryPosition: trimmedPrimaryPosition,
                                    secondaryPosition: trimmedSecondaryPosition,
                                    isChild: isChild
                                )
                            )
                            if saved {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!canSubmit || isSaving)
                }
            }
        }
    }

    private var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPhone: String {
        phone.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLicence: String {
        licence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPrimaryPosition: String {
        primaryPosition.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSecondaryPosition: String {
        secondaryPosition.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedFirstName.isEmpty && (isChild || trimmedEmail.isEmpty || isValidEmail(trimmedEmail))
    }

    private func isValidEmail(_ value: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

private struct AdultInvitePrerequisitesPayload {
    let lastName: String
    let email: String
    let phone: String
}

private struct CompleteAdultInviteInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var lastName: String
    @State private var email: String
    @State private var phone: String

    let isSaving: Bool
    let onSubmit: (AdultInvitePrerequisitesPayload) async -> Bool

    init(
        player: Player,
        isSaving: Bool,
        onSubmit: @escaping (AdultInvitePrerequisitesPayload) async -> Bool
    ) {
        _lastName = State(initialValue: player.lastName ?? "")
        _email = State(initialValue: player.email ?? "")
        _phone = State(initialValue: player.phone ?? "")
        self.isSaving = isSaving
        self.onSubmit = onSubmit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Informations requises") {
                    TextField("Nom", text: $lastName)
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.emailAddress)
                    TextField("Téléphone", text: $phone)
                        .keyboardType(.phonePad)
                }

                Section {
                    Text("Nom, e-mail et téléphone sont requis pour inviter un joueur adulte.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !trimmedEmail.isEmpty, !isValidEmail(trimmedEmail) {
                        Text("Merci de saisir une adresse e-mail valide.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Compléter la fiche")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Enregistrement…" : "Enregistrer") {
                        Task {
                            let saved = await onSubmit(
                                AdultInvitePrerequisitesPayload(
                                    lastName: trimmedLastName,
                                    email: trimmedEmail,
                                    phone: trimmedPhone
                                )
                            )
                            if saved {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!canSubmit || isSaving)
                }
            }
        }
    }

    private var trimmedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPhone: String {
        phone.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedLastName.isEmpty && !trimmedEmail.isEmpty && !trimmedPhone.isEmpty && isValidEmail(trimmedEmail)
    }

    private func isValidEmail(_ value: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

private struct InvitePlayerSheet: View {
    let url: URL
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Partagez ce QR code ou ce lien pour finaliser le compte.")
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
