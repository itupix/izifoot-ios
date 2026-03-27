import SwiftUI

struct MainShellView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var selectedTab: AppTab = .planning

    var body: some View {
        TabView(selection: $selectedTab) {
            PlanningHomeView()
                .tabItem {
                    Label("Planning", systemImage: "calendar")
                }
                .tag(AppTab.planning)

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
    }
}
