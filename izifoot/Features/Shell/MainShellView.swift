import Combine
import SwiftUI

struct MainShellView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var selectedTab: AppTab = .planning
    @State private var unreadMessagesCount = 0
    private let api = IzifootAPI()
    private let unreadTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $selectedTab) {
            PlanningHomeView()
                .tabItem {
                    Label("Planning", systemImage: "calendar")
                }
                .tag(AppTab.planning)

            MessagesView()
                .tabItem {
                    Label("Messages", systemImage: "message")
                }
                .badge(unreadMessagesCount > 0 ? unreadMessagesCount : 0)
                .tag(AppTab.messages)

            if authStore.me?.role.canEditSportData == true {
                DrillsHomeView()
                    .tabItem {
                        Label("Exercices", systemImage: "figure.indoor.soccer")
                    }
                    .tag(AppTab.drills)

                PlayersHomeView()
                    .tabItem {
                        Label("Mon équipe", systemImage: "person.3")
                    }
                    .tag(AppTab.players)
            }
        }
        .task {
            if let role = authStore.me?.role {
                selectedTab = role.defaultTab
            }
        }
        .task(id: authStore.me?.id) {
            await refreshUnreadCount()
        }
        .onReceive(unreadTimer) { _ in
            Task { await refreshUnreadCount() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .teamMessagesDidRefresh)) { _ in
            Task { await refreshUnreadCount() }
        }
    }

    private func refreshUnreadCount() async {
        guard authStore.me != nil else {
            unreadMessagesCount = 0
            return
        }

        do {
            unreadMessagesCount = try await api.unreadTeamMessagesCount()
        } catch {
            unreadMessagesCount = 0
        }
    }
}
