import SwiftUI

@main
struct IzifootApp: App {
    @StateObject private var authStore = AuthStore()
    @StateObject private var teamScopeStore = TeamScopeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authStore)
                .environmentObject(teamScopeStore)
                .task {
                    await authStore.restoreSessionIfPossible()
                    await teamScopeStore.bootstrap(authStore: authStore)
                }
                .onChange(of: authStore.me?.id) { _, _ in
                    Task {
                        await teamScopeStore.bootstrap(authStore: authStore)
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
