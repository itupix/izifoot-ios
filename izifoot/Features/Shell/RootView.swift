import SwiftUI

struct RootView: View {
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        Group {
            if authStore.isRestoringSession && authStore.me == nil {
                ProgressView("Chargement")
            } else if authStore.isAuthenticated {
                MainShellView()
            } else {
                AuthView()
            }
        }
        .scrollBounceBehavior(.always)
    }
}
