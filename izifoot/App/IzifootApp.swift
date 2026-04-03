import SwiftUI

@main
struct IzifootApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    @StateObject private var authStore = AuthStore()
    @StateObject private var teamScopeStore = TeamScopeStore()
    private let pushManager = PushNotificationManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authStore)
                .environmentObject(teamScopeStore)
                .task {
                    pushManager.configure()
                    await authStore.restoreSessionIfPossible()
                    await teamScopeStore.bootstrap(authStore: authStore)
                    await MainActor.run {
                        pushManager.updateAuthenticatedUserID(authStore.me?.id)
                    }
                }
                .onChange(of: authStore.me?.id) { _, _ in
                    Task {
                        await teamScopeStore.bootstrap(authStore: authStore)
                        await MainActor.run {
                            pushManager.updateAuthenticatedUserID(authStore.me?.id)
                        }
                    }
                }
                .onChange(of: teamScopeStore.selectedTeamID) { _, _ in
                    if let selectedTeamID = teamScopeStore.selectedTeamID {
                        AppSession.shared.activeTeamID = selectedTeamID
                    } else {
                        AppSession.shared.activeTeamID = nil
                    }
                }
        }
    }
}
