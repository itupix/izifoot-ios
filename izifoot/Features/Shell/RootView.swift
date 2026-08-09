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
        .rootScrollBounceBehaviorCompatibility()
    }
}

private extension View {
    @ViewBuilder
    func rootScrollBounceBehaviorCompatibility() -> some View {
        if #available(iOS 16.4, *) {
            self.scrollBounceBehavior(.always)
        } else {
            self
        }
    }
}
