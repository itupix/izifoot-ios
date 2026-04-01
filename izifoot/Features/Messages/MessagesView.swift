import SwiftUI
import Combine

extension Notification.Name {
    static let teamMessagesDidRefresh = Notification.Name("teamMessagesDidRefresh")
}

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published private(set) var messages: [TeamMessage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published var draft = ""
    @Published var errorMessage: String?

    private var pendingLikes = Set<String>()
    private let api: IzifootAPI

    init(api: IzifootAPI = IzifootAPI()) {
        self.api = api
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            messages = try await api.teamMessages()
                .sorted { lhs, rhs in lhs.createdAt > rhs.createdAt }
            NotificationCenter.default.post(name: .teamMessagesDidRefresh, object: nil)
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func sendIfPossible() async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let created = try await api.createTeamMessage(content: content)
            draft = ""
            messages.insert(created, at: 0)
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func toggleLike(_ message: TeamMessage) async {
        guard !pendingLikes.contains(message.id) else { return }
        pendingLikes.insert(message.id)
        defer { pendingLikes.remove(message.id) }

        do {
            let reaction: TeamMessageReactionResponse
            if message.likedByMe {
                reaction = try await api.unlikeTeamMessage(id: message.id)
            } else {
                reaction = try await api.likeTeamMessage(id: message.id)
            }

            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                let current = messages[index]
                messages[index] = TeamMessage(
                    id: current.id,
                    teamId: current.teamId,
                    clubId: current.clubId,
                    content: current.content,
                    createdAt: current.createdAt,
                    updatedAt: current.updatedAt,
                    author: current.author,
                    likesCount: reaction.likesCount,
                    likedByMe: reaction.likedByMe
                )
            }
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }
}

struct MessagesView: View {
    @EnvironmentObject private var authStore: AuthStore
    @StateObject private var viewModel = MessagesViewModel()
    @FocusState private var isComposerFocused: Bool

    private var canPost: Bool {
        authStore.me?.role.canEditSportData == true
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Canal de l'équipe")
                    .font(.title3.weight(.semibold))
                Text("Messages envoyés par le staff à tous les joueurs et parents.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)

            if canPost {
                composer
            }

            if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }

            content
        }
        .navigationTitle("Messages")
        .task {
            await viewModel.load()
        }
        .onTapGesture {
            isComposerFocused = false
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Terminer") {
                    isComposerFocused = false
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Canal officiel coach/direction vers joueurs et parents")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.draft)
                .focused($isComposerFocused)
                .frame(minHeight: 88)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.separator), lineWidth: 1)
                )

            HStack {
                Text("\(viewModel.draft.count)/2000")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await viewModel.sendIfPossible() }
                    isComposerFocused = false
                } label: {
                    if viewModel.isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Envoyer", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSending || viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ScrollView {
                ProgressView("Chargement des messages...")
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity)
            }
            .refreshable {
                await viewModel.load()
            }
        } else if viewModel.messages.isEmpty {
            ScrollView {
                VStack(spacing: 10) {
                    Image(systemName: "message")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Aucun message pour le moment")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 24)
            }
            .refreshable {
                await viewModel.load()
            }
        } else {
            List(viewModel.messages) { message in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(authorLabel(message.author))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formattedDate(message.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message.content)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack {
                                Spacer()
                                Button {
                                    Task { await viewModel.toggleLike(message) }
                                } label: {
                                    Label("\(message.likesCount)", systemImage: message.likedByMe ? "heart.fill" : "heart")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(message.likedByMe ? .pink : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )

                        Spacer(minLength: 24)
                    }
                }
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.load()
            }
        }
    }

    private func authorLabel(_ author: TeamMessageAuthor?) -> String {
        let fullName = [author?.firstName, author?.lastName]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")
        if !fullName.isEmpty { return fullName }
        return "Staff"
    }

    private func formattedDate(_ isoDate: String) -> String {
        if let date = Self.iso8601FormatterWithFractionalSeconds.date(from: isoDate)
            ?? Self.iso8601Formatter.date(from: isoDate) {
            return Self.humanDateFormatter.string(from: date)
        }
        return isoDate
    }

    private static let iso8601FormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let humanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
}
