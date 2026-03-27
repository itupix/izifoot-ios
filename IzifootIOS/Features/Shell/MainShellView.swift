import SwiftUI

struct MainShellView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var selectedTab: AppTab = .planning

    var body: some View {
        TabView(selection: $selectedTab) {
            if authStore.me?.role == .direction {
                ClubHomeView()
                    .tabItem {
                        Label("Mon club", systemImage: "building.2")
                    }
                    .tag(AppTab.club)
            }

            PlanningHomeView()
                .tabItem {
                    Label("Planning", systemImage: "calendar")
                }
                .tag(AppTab.planning)

            if authStore.me?.role?.canEditSportData == true {
                DrillsHomeView()
                    .tabItem {
                        Label("Exercices", systemImage: "figure.strengthtraining.traditional")
                    }
                    .tag(AppTab.drills)

                PlayersHomeView()
                    .tabItem {
                        Label("Mon équipe", systemImage: "person.3")
                    }
                    .tag(AppTab.players)

                StatsHomeView()
                    .tabItem {
                        Label("Stats", systemImage: "chart.bar")
                    }
                    .tag(AppTab.stats)
            }

            AccountView()
                .tabItem {
                    Label("Compte", systemImage: "person.crop.circle")
                }
                .tag(AppTab.account)
        }
        .task {
            if let role = authStore.me?.role {
                selectedTab = role.defaultTab
            }
        }
    }
}
