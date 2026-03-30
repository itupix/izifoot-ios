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
            errorMessage = error.localizedDescription
        }
    }

    func invitePlayer(id: String) async {
        isInviting = true
        defer { isInviting = false }

        do {
            let response = try await api.invitePlayer(id: id)
            invitationStatus = .fromAPI(response.status)
            if let inviteUrl = response.inviteUrl, !inviteUrl.isEmpty, let url = URL(string: inviteUrl) {
                inviteURL = url
                isInviteSheetPresented = true
            } else {
                errorMessage = "Invitation envoyée mais lien indisponible."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PlayerDetailView: View {
    let playerID: String

    @StateObject private var viewModel = PlayerDetailViewModel()

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

                Section("Contact") {
                    if let email = player.email {
                        LabeledContent("Email", value: email)
                    }
                    if let phone = player.phone {
                        LabeledContent("Téléphone", value: phone)
                    }
                }

                Section("Invitation compte") {
                    LabeledContent("Statut", value: invitationStatusLabel(viewModel.invitationStatus))
                    if viewModel.invitationStatus != .accepted {
                        Button(viewModel.isInviting ? "Envoi…" : (viewModel.invitationStatus == .pending ? "Renvoyer l'invitation" : "Inviter")) {
                            Task { await viewModel.invitePlayer(id: playerID) }
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
