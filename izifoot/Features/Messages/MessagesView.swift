import Combine
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

extension Notification.Name {
    static let teamMessagesDidRefresh = Notification.Name("teamMessagesDidRefresh")
    static let messagesUnreadCountDidChange = Notification.Name("messagesUnreadCountDidChange")
}

private extension MessageConversation {
    var isAnnouncementsConversation: Bool {
        type == "ANNOUNCEMENTS"
    }

    func withInvitationStatus(_ status: ConversationInvitationStatus?) -> MessageConversation {
        MessageConversation(
            id: id,
            type: type,
            playerId: playerId,
            title: title,
            subtitle: subtitle,
            lastMessagePreview: lastMessagePreview,
            lastMessageAt: lastMessageAt,
            invitationStatus: status
        )
    }

    var isDisabledCoachConversation: Bool {
        type == "COACH" && invitationStatus == .none
    }

    var isPendingCoachInvitation: Bool {
        type == "COACH" && invitationStatus == .pending
    }

    var coachConversationStatusLabel: String? {
        if isDisabledCoachConversation {
            return "Invitation requise"
        }
        if isPendingCoachInvitation {
            return "Invitation en attente"
        }
        return nil
    }
}

@MainActor
final class ConversationUnreadStore: ObservableObject {
    @Published private(set) var revision = 0

    private let defaults = UserDefaults.standard
    private let keyPrefix = "izifoot.messages.lastSeen."
    private var currentUserID: String?

    func setCurrentUserID(_ userID: String?) {
        guard currentUserID != userID else { return }
        currentUserID = userID
        revision += 1
    }

    func hasUnread(_ conversation: MessageConversation) -> Bool {
        if conversation.isDisabledCoachConversation { return false }
        guard let lastMessageAt = conversation.lastMessageAt,
              let lastDate = DateFormatters.parseISODate(lastMessageAt),
              let userID = currentUserID,
              !userID.isEmpty else {
            return false
        }

        let seenTimestamp = defaults.double(forKey: storageKey(userID: userID, conversationID: conversation.id))
        guard seenTimestamp > 0 else { return true }
        return lastDate.timeIntervalSince1970 > seenTimestamp
    }

    func markConversationRead(conversationID: String, lastMessageAt: String?) {
        guard let userID = currentUserID, !userID.isEmpty else { return }
        let timestamp = DateFormatters.parseISODate(lastMessageAt ?? "")?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        defaults.set(timestamp, forKey: storageKey(userID: userID, conversationID: conversationID))
        revision += 1
    }

    private func storageKey(userID: String, conversationID: String) -> String {
        "\(keyPrefix)\(userID).\(conversationID)"
    }
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

    private struct MessagesListCachePayload: Codable {
        let conversations: [MessageConversation]
    }

    func updateConversationInvitationStatus(
        id: String,
        invitationStatus: ConversationInvitationStatus,
        cacheKey: String
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let conversation = conversations[index]
        guard conversation.type == "COACH", conversation.invitationStatus != invitationStatus else { return }

        conversations[index] = conversation.withInvitationStatus(invitationStatus)
        let updatedConversations = conversations
        Task {
            await PersistentDataCache.shared.write(
                MessagesListCachePayload(conversations: updatedConversations),
                forKey: cacheKey
            )
        }
    }

    func markConversationUnavailable(id: String, cacheKey: String) {
        updateConversationInvitationStatus(id: id, invitationStatus: .none, cacheKey: cacheKey)
    }

    func markConversationPending(id: String, cacheKey: String) {
        updateConversationInvitationStatus(id: id, invitationStatus: .pending, cacheKey: cacheKey)
    }

    func load(cacheKey: String, teamID: String? = nil, forceRefresh: Bool = false) async {
        var hasCachedData = false
        if !forceRefresh,
           let cached = await PersistentDataCache.shared.read(MessagesListCachePayload.self, forKey: cacheKey) {
            conversations = cached.conversations
            hasCachedData = true
            errorMessage = nil
        }

        do {
            conversations = try await api.messageConversations(teamID: teamID)
            await PersistentDataCache.shared.write(MessagesListCachePayload(conversations: conversations), forKey: cacheKey)
            errorMessage = nil
        } catch {
            if !error.isCancellationError, !hasCachedData { errorMessage = error.localizedDescription }
        }
    }
}

@MainActor
final class ConversationThreadViewModel: ObservableObject {
    @Published private(set) var messages: [ConversationMessage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published private(set) var isGeneratingInvite = false
    @Published private(set) var isConversationUnavailable = false
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
            isConversationUnavailable = false
            errorMessage = nil
        } catch {
            if !error.isCancellationError { handleThreadError(error) }
        }
    }

    func sendIfPossible(canSend: Bool) async {
        guard canSend, !isConversationUnavailable else { return }
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        isSending = true
        defer { isSending = false }

        do {
            let created = try await api.sendConversationMessage(conversationID: conversation.id, content: content)
            draft = ""
            messages.append(created)
            isConversationUnavailable = false
            errorMessage = nil

            if conversation.isAnnouncementsConversation {
                NotificationCenter.default.post(name: .teamMessagesDidRefresh, object: nil)
            }
        } catch {
            if !error.isCancellationError { handleThreadError(error) }
        }
    }

    func createInviteForConversation() async -> URL? {
        guard conversation.type == "COACH",
              let playerId = conversation.playerId,
              !playerId.isEmpty else {
            errorMessage = "Invitation indisponible pour cette conversation."
            return nil
        }

        isGeneratingInvite = true
        defer { isGeneratingInvite = false }

        do {
            let response = try await api.invitePlayer(id: playerId)
            guard let inviteUrl = response.inviteUrl,
                  !inviteUrl.isEmpty,
                  let url = URL(string: inviteUrl) else {
                errorMessage = "Lien d'invitation indisponible."
                return nil
            }

            errorMessage = nil
            await load()
            return url
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
            return nil
        }
    }

    private func handleThreadError(_ error: Error) {
        if let apiError = error as? APIError,
           case let APIError.server(status, _) = apiError,
           status == 403,
           conversation.type == "COACH" {
            isConversationUnavailable = true
            draft = ""
            errorMessage = nil
            return
        }

        errorMessage = error.localizedDescription
    }
}

struct MessagesView: View {
    @EnvironmentObject private var authStore: AuthStore
    @StateObject private var viewModel = MessagesListViewModel()
    @StateObject private var unreadStore = ConversationUnreadStore()
    private var dataCacheKey: String { "messages-home-v3-\(authStore.me?.id ?? "anonymous")" }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.conversations.isEmpty {
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
                        if conversation.isDisabledCoachConversation {
                            ConversationRow(
                                conversation: conversation,
                                showsUnreadDot: false,
                                isDisabled: true
                            )
                        } else {
                            NavigationLink {
                                ConversationThreadView(conversation: conversation) { latestMessageAt in
                                    unreadStore.markConversationRead(conversationID: conversation.id, lastMessageAt: latestMessageAt)
                                } onConversationUnavailable: { unavailableConversationID in
                                    viewModel.markConversationUnavailable(id: unavailableConversationID, cacheKey: dataCacheKey)
                                    publishUnreadCount()
                                } onInvitationStatusChanged: { conversationID, invitationStatus in
                                    if invitationStatus == .pending {
                                        viewModel.markConversationPending(id: conversationID, cacheKey: dataCacheKey)
                                    } else if invitationStatus == .none {
                                        viewModel.markConversationUnavailable(id: conversationID, cacheKey: dataCacheKey)
                                    }
                                    publishUnreadCount()
                                }
                            } label: {
                                ConversationRow(
                                    conversation: conversation,
                                    showsUnreadDot: unreadStore.hasUnread(conversation),
                                    isDisabled: false
                                )
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .task {
                unreadStore.setCurrentUserID(authStore.me?.id)
                await viewModel.load(cacheKey: dataCacheKey)
                publishUnreadCount()
            }
            .onChange(of: authStore.me?.id) { _, newValue in
                unreadStore.setCurrentUserID(newValue)
                publishUnreadCount()
            }
            .refreshable {
                await viewModel.load(cacheKey: dataCacheKey, forceRefresh: true)
                publishUnreadCount()
            }
            .onAppear {
                publishUnreadCount()
            }
            .alert("Erreur", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { _ in viewModel.errorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: unreadStore.revision) { _, _ in
                publishUnreadCount()
            }
            .onChange(of: conversationsSignature) { _, _ in
                publishUnreadCount()
            }
        }
    }

    private var conversationsSignature: String {
        viewModel.conversations
            .map { "\($0.id)|\($0.lastMessageAt ?? "")" }
            .joined(separator: "||")
    }

    private func publishUnreadCount() {
        let unreadCount = viewModel.conversations.reduce(into: 0) { result, conversation in
            if unreadStore.hasUnread(conversation) { result += 1 }
        }
        NotificationCenter.default.post(
            name: .messagesUnreadCountDidChange,
            object: nil,
            userInfo: ["count": unreadCount]
        )
    }
}

private struct ConversationRow: View {
    let conversation: MessageConversation
    let showsUnreadDot: Bool
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(conversation.isAnnouncementsConversation ? Color.orange.opacity(0.2) : Color.accentColor.opacity(0.18))
                .frame(width: 42, height: 42)
                .overlay {
                    Text(initials)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(conversation.isAnnouncementsConversation ? .orange : .accentColor)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if showsUnreadDot {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }
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

                if let statusLabel = conversation.coachConversationStatusLabel {
                    Text(statusLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(conversation.isDisabledCoachConversation ? .orange : .secondary)
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
        .opacity(isDisabled ? 0.52 : 1)
    }

    private var initials: String {
        if conversation.isAnnouncementsConversation { return "A" }
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
    @State private var invitePreviewURL: URL?
    @State private var shareURL: URL?
    let onOpened: (String?) -> Void
    let onConversationUnavailable: (String) -> Void
    let onInvitationStatusChanged: (String, ConversationInvitationStatus) -> Void

    init(
        conversation: MessageConversation,
        onOpened: @escaping (String?) -> Void = { _ in },
        onConversationUnavailable: @escaping (String) -> Void = { _ in },
        onInvitationStatusChanged: @escaping (String, ConversationInvitationStatus) -> Void = { _, _ in }
    ) {
        _viewModel = StateObject(wrappedValue: ConversationThreadViewModel(conversation: conversation))
        self.onOpened = onOpened
        self.onConversationUnavailable = onConversationUnavailable
        self.onInvitationStatusChanged = onInvitationStatusChanged
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage,
               !error.isEmpty,
               !viewModel.isConversationUnavailable {
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

            if viewModel.isConversationUnavailable {
                ConversationInviteUnavailableCard(
                    isLoading: viewModel.isGeneratingInvite,
                    errorMessage: viewModel.errorMessage,
                    onShowQRCode: handleShowQRCode,
                    onShareLink: handleShareInviteLink
                )
                .background(.ultraThinMaterial)
            } else {
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
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                    }
                    .disabled(!canSend || viewModel.isSending || viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle(viewModel.conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            onOpened(viewModel.conversation.lastMessageAt)
            PushNotificationManager.shared.clearMessageNotifications(for: viewModel.conversation.id)
            await viewModel.load()
            onOpened(viewModel.messages.last?.createdAt ?? viewModel.conversation.lastMessageAt)
        }
        .refreshable {
            await viewModel.load()
        }
        .sheet(isPresented: Binding(
            get: { invitePreviewURL != nil },
            set: { if !$0 { invitePreviewURL = nil } }
        )) {
            if let url = invitePreviewURL {
                ConversationInviteSheet(url: url)
            }
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let url = shareURL {
                ActivityShareSheet(items: [url])
            }
        }
        .onChange(of: viewModel.isConversationUnavailable) { _, isUnavailable in
            if isUnavailable {
                isComposerFocused = false
                onConversationUnavailable(viewModel.conversation.id)
            }
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
        if viewModel.isConversationUnavailable { return false }
        if viewModel.conversation.isAnnouncementsConversation {
            return authStore.me?.role.canEditSportData == true
        }
        return true
    }

    private func handleShowQRCode() {
        Task {
            guard let url = await viewModel.createInviteForConversation() else { return }
            onInvitationStatusChanged(viewModel.conversation.id, .pending)
            invitePreviewURL = url
        }
    }

    private func handleShareInviteLink() {
        Task {
            guard let url = await viewModel.createInviteForConversation() else { return }
            onInvitationStatusChanged(viewModel.conversation.id, .pending)
            shareURL = url
        }
    }
}

private struct ConversationInviteUnavailableCard: View {
    let isLoading: Bool
    let errorMessage: String?
    let onShowQRCode: () -> Void
    let onShareLink: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Messagerie directe non disponible", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.footnote.weight(.semibold))

            Text("Invitez cette personne sur izifoot pour débloquer la conversation, puis partagez le QR code ou le lien d'accès.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    onShowQRCode()
                } label: {
                    Label(isLoading ? "Préparation…" : "Afficher le QR code", systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)

                Button {
                    onShareLink()
                } label: {
                    Label("Envoyer le lien", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

private struct ConversationInviteSheet: View {
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

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
