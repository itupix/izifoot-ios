import Foundation
import UIKit
import UserNotifications

final class PushNotificationManager: NSObject {
    static let shared = PushNotificationManager()

    private let api = IzifootAPI()
    private var authenticatedUserID: String?
    private var deviceTokenHex: String?
    private var lastSyncedKey: String?
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
        Task { await self.syncTokenIfPossible() }
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
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    guard granted else { return }
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            default:
                break
            }
        }
    }

    private func syncTokenIfPossible() async {
        guard let userID = authenticatedUserID, !userID.isEmpty else { return }
        guard let token = deviceTokenHex, !token.isEmpty else { return }

        let syncKey = "\(userID)|\(token)"
        if lastSyncedKey == syncKey { return }

        do {
            try await api.registerPushToken(token, enabled: true)
            lastSyncedKey = syncKey
            print("[push] token synced for user \(userID)")
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

    @objc private func handleDidBecomeActive() {
        requestAuthorizationAndRegisterIfNeeded()
        UIApplication.shared.applicationIconBadgeNumber = 0
        Task { await self.syncTokenIfPossible() }
        Task { try? await self.api.resetPushBadge() }
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

            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = 0
            }

            Task {
                try? await self.api.resetPushBadge()
            }
        }
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
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
