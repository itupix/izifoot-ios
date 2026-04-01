import Combine
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

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
    @Published private(set) var deletingParentID: String?
    @Published fileprivate var invitationStatus: PlayerInvitationStatusValue = .none
    @Published private(set) var inviteURL: URL?
    @Published var isInviteSheetPresented = false
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI = IzifootAPI()) {
        self.api = api
    }

    func load(id: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            player = try await api.player(id: id)
            do {
                let invitation = try await api.playerInvitationStatus(id: id)
                invitationStatus = .fromAPI(invitation.status)
            } catch {
                invitationStatus = .none
            }
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
    @State private var isParentInviteSheetPresented = false
    @State private var parentInviteEmail = ""
    @State private var parentInvitePhone = ""
    @State private var parentToDelete: Player.ParentContact?

    var body: some View {
        List {
            if let player = viewModel.player {
                Section("Identité") {
                    LabeledContent("Nom", value: player.name)
                    if let firstName = player.firstName {
                        LabeledContent("Prénom", value: firstName)
                    }
                    if let lastName = player.lastName {
                        LabeledContent("Nom de famille", value: lastName)
                    }
                }

                Section("Sport") {
                    if let primaryPosition = player.primaryPosition {
                        LabeledContent("Poste principal", value: primaryPosition)
                    }
                    if let secondaryPosition = player.secondaryPosition {
                        LabeledContent("Poste secondaire", value: secondaryPosition)
                    }
                }

                if !player.isChild {
                    Section("Contact") {
                        if let email = player.email {
                            LabeledContent("Email", value: email)
                        }
                        if let phone = player.phone {
                            LabeledContent("Téléphone", value: phone)
                        }
                    }
                }

                if player.isChild {
                    Section("Parents") {
                        if player.parentContacts.isEmpty {
                            Text("Aucun parent lié")
                                .foregroundStyle(.secondary)
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
                        }
                    }
                }

                Section("Invitation compte") {
                    LabeledContent("Statut", value: invitationStatusLabel(viewModel.invitationStatus))
                    if viewModel.invitationStatus != .accepted || player.isChild {
                        Button(viewModel.isInviting ? "Envoi…" : (viewModel.invitationStatus == .pending ? "Renvoyer l'invitation" : "Inviter")) {
                            if player.isChild {
                                parentInviteEmail = ""
                                parentInvitePhone = ""
                                isParentInviteSheetPresented = true
                            } else {
                                Task { await viewModel.invitePlayer(id: playerID) }
                            }
                        }
                        .disabled(viewModel.isInviting)
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
        .task {
            await viewModel.load(id: playerID)
        }
        .sheet(isPresented: $viewModel.isInviteSheetPresented) {
            if let url = viewModel.inviteURL {
                InvitePlayerSheet(url: url)
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

    private func invitationStatusLabel(_ status: PlayerInvitationStatusValue) -> String {
        switch status {
        case .none: return "Non invité"
        case .pending: return "Invitation en attente"
        case .accepted: return "Compte activé"
        }
    }

    private func displayValue(_ value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "—" }
        return value
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
