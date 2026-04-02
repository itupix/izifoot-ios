import Foundation
import UIKit
import UserNotifications

final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    private let api = IzifootAPI()
    private var authenticatedUserID: String?
    private var deviceTokenHex: String?
    private var lastSyncedKey: String?

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
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
        } catch {
            // Silent retry on next app foreground / token refresh.
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
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationManager.shared.handleRegisteredDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[push] APNs registration failed: \(error.localizedDescription)")
        #endif
    }
}
