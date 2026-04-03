import Combine
import SwiftUI
import UIKit

struct MainShellView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var selectedTab: AppTab = .planning
    @State private var unreadMessagesCount = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            PlanningHomeView()
                .tabItem {
                    Label("Planning", systemImage: "calendar")
                }
                .tag(AppTab.planning)

            NavigationStack {
                MessagesView()
            }
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
            unreadMessagesCount = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .messagesUnreadCountDidChange)) { output in
            let count = (output.userInfo?["count"] as? Int) ?? 0
            unreadMessagesCount = max(0, count)
            if count == 0 {
                UIApplication.shared.applicationIconBadgeNumber = 0
            }
        }
    }
}
