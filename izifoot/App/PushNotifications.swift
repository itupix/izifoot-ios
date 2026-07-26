import Foundation
import UIKit
import UserNotifications

final class PushNotificationManager: NSObject {
    static let shared = PushNotificationManager()

    private let api = IzifootAPI()
    private var authenticatedUserID: String?
    private var deviceTokenHex: String?
    private var lastSyncedKey: String?
    private var isPushPermissionEnabled = false
    private var didResetBadgeAfterUnreadClear = false
    private var isConfigured = false
    private var retryTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        UNUserNotificationCenter.current().delegate = self
        requestAuthorizationAndRegisterIfNeeded()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @MainActor
    func updateAuthenticatedUserID(_ userID: String?) {
        if authenticatedUserID != userID {
            authenticatedUserID = userID
            lastSyncedKey = nil
        }
        guard userID != nil else { return }
        requestAuthorizationAndRegisterIfNeeded()
    }

    func handleRegisteredDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        guard !token.isEmpty else { return }
        deviceTokenHex = token
        print("[push] APNs token received: \(token.prefix(16))...")
        Task { await self.syncTokenIfPossible() }
    }

    private func requestAuthorizationAndRegisterIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.updatePushPermissionState(enabled: true)
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
                    guard let self else { return }
                    self.updatePushPermissionState(enabled: granted)
                    guard granted else { return }
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            default:
                self.updatePushPermissionState(enabled: false)
            }
        }
    }

    private func syncTokenIfPossible() async {
        guard let userID = authenticatedUserID, !userID.isEmpty else { return }
        guard let token = deviceTokenHex, !token.isEmpty else { return }

        let enabled = isPushPermissionEnabled
        let syncKey = "\(userID)|\(token)|\(enabled)"
        if lastSyncedKey == syncKey { return }

        do {
            try await api.registerPushToken(token, enabled: enabled)
            retryTask?.cancel()
            retryTask = nil
            lastSyncedKey = syncKey
            print("[push] token sync (\(enabled ? "enabled" : "disabled")) for user \(userID)")
        } catch {
            print("[push] token sync failed: \(error.localizedDescription)")
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.syncTokenIfPossible()
            }
        }
    }

    private func updatePushPermissionState(enabled: Bool) {
        isPushPermissionEnabled = enabled
        Task { await self.syncTokenIfPossible() }
    }

    @objc private func handleDidBecomeActive() {
        requestAuthorizationAndRegisterIfNeeded()
        notifyMessagesRefreshRequested()
    }

    func clearMessageNotifications(for conversationID: String?) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
            let identifiers = notifications.compactMap { item -> String? in
                let userInfo = item.request.content.userInfo
                guard (userInfo["type"] as? String) == "MESSAGE" else { return nil }
                if let conversationID, !conversationID.isEmpty {
                    return (userInfo["conversationId"] as? String) == conversationID ? item.request.identifier : nil
                }
                return item.request.identifier
            }

            if !identifiers.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: identifiers)
            }
        }
    }

    @MainActor
    func syncApplicationBadge(unreadCount: Int) {
        let sanitizedCount = max(0, unreadCount)
        if sanitizedCount > 0 {
            didResetBadgeAfterUnreadClear = false
            if UIApplication.shared.applicationIconBadgeNumber == 0 {
                UIApplication.shared.applicationIconBadgeNumber = sanitizedCount
            }
            return
        }

        let shouldResetRemoteBadge = !didResetBadgeAfterUnreadClear
        UIApplication.shared.applicationIconBadgeNumber = 0
        guard shouldResetRemoteBadge else { return }

        didResetBadgeAfterUnreadClear = true
        Task { try? await self.api.resetPushBadge() }
    }

    private func notifyMessagesRefreshRequested() {
        NotificationCenter.default.post(name: .messagesRefreshRequested, object: nil)
    }

    private func handleMessageNotificationIfNeeded(userInfo: [AnyHashable: Any]) {
        guard (userInfo["type"] as? String) == "MESSAGE" else { return }
        notifyMessagesRefreshRequested()
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handleMessageNotificationIfNeeded(userInfo: notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleMessageNotificationIfNeeded(userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }
}

final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PushNotificationManager.shared.configure()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationManager.shared.handleRegisteredDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[push] APNs registration failed: \(error.localizedDescription)")
    }
}
