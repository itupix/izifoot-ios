import Combine
import SwiftUI

extension Notification.Name {
    static let teamMessagesDidRefresh = Notification.Name("teamMessagesDidRefresh")
}

@MainActor
final class MessagesListViewModel: ObservableObject {
    @Published private(set) var conversations: [MessageConversation] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI = IzifootAPI()) {
        self.api = api
    }

    func load(teamID: String? = nil) async {
        isLoading = true
        defer { isLoading = false }

        do {
            conversations = try await api.messageConversations(teamID: teamID)
            errorMessage = nil
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }
}

@MainActor
final class ConversationThreadViewModel: ObservableObject {
    @Published private(set) var messages: [ConversationMessage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published var draft = ""
    @Published var errorMessage: String?

    let conversation: MessageConversation
    private let api: IzifootAPI

    init(conversation: MessageConversation, api: IzifootAPI = IzifootAPI()) {
        self.conversation = conversation
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await api.conversationMessages(conversationID: conversation.id)
            messages = response.items
            errorMessage = nil
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func sendIfPossible(canSend: Bool) async {
        guard canSend else { return }
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        isSending = true
        defer { isSending = false }

        do {
            let created = try await api.sendConversationMessage(conversationID: conversation.id, content: content)
            draft = ""
            messages.append(created)
            errorMessage = nil

            if conversation.type == "ANNOUNCEMENTS" {
                NotificationCenter.default.post(name: .teamMessagesDidRefresh, object: nil)
            }
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }
}

struct MessagesView: View {
    @EnvironmentObject private var authStore: AuthStore
    @StateObject private var viewModel = MessagesListViewModel()

    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Chargement")
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if viewModel.conversations.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Aucune conversation")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
                .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.conversations) { conversation in
                    NavigationLink {
                        ConversationThreadView(conversation: conversation)
                    } label: {
                        ConversationRow(conversation: conversation)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Messages")
        .appChrome()
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
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

private struct ConversationRow: View {
    let conversation: MessageConversation

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(conversation.type == "ANNOUNCEMENTS" ? Color.orange.opacity(0.2) : Color.accentColor.opacity(0.18))
                .frame(width: 42, height: 42)
                .overlay {
                    Text(initials)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(conversation.type == "ANNOUNCEMENTS" ? .orange : .accentColor)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if let timestamp = formattedTime(conversation.lastMessageAt) {
                        Text(timestamp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let subtitle = conversation.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let preview = conversation.lastMessagePreview, !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var initials: String {
        if conversation.type == "ANNOUNCEMENTS" { return "A" }
        let words = conversation.title.split(separator: " ")
        if words.count >= 2 {
            return "\(words[0].prefix(1))\(words[1].prefix(1))".uppercased()
        }
        return String(conversation.title.prefix(1)).uppercased()
    }

    private func formattedTime(_ raw: String?) -> String? {
        guard let raw, let date = DateFormatters.parseISODate(raw) else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct ConversationThreadView: View {
    @EnvironmentObject private var authStore: AuthStore
    @StateObject private var viewModel: ConversationThreadViewModel
    @FocusState private var isComposerFocused: Bool

    init(conversation: MessageConversation) {
        _viewModel = StateObject(wrappedValue: ConversationThreadViewModel(conversation: conversation))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleRow(
                                message: message,
                                isMine: message.sender?.id == authStore.me?.id
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    guard let last = viewModel.messages.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $viewModel.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($isComposerFocused)
                    .lineLimit(1 ... 4)
                    .disabled(!canSend)

                Button {
                    Task {
                        await viewModel.sendIfPossible(canSend: canSend)
                        isComposerFocused = false
                    }
                } label: {
                    if viewModel.isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                    }
                }
                .disabled(!canSend || viewModel.isSending || viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
            .background(.ultraThinMaterial)
        }
        .navigationTitle(viewModel.conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
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

    private var canSend: Bool {
        if viewModel.conversation.type == "ANNOUNCEMENTS" {
            return authStore.me?.role.canEditSportData == true
        }
        return true
    }
}

private struct MessageBubbleRow: View {
    let message: ConversationMessage
    let isMine: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 48) }

            if !isMine {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text(senderInitial)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if !isMine {
                    Text(senderName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isMine ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
                    )
                    .foregroundStyle(isMine ? Color.white : Color.primary)

                if let date = DateFormatters.parseISODate(message.createdAt) {
                    Text(date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 280, alignment: isMine ? .trailing : .leading)

            if !isMine { Spacer(minLength: 48) }
        }
    }

    private var senderName: String {
        let first = message.sender?.firstName ?? ""
        let last = message.sender?.lastName ?? ""
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? "Membre" : full
    }

    private var senderInitial: String {
        let value = senderName.prefix(1)
        return String(value).uppercased()
    }
}
