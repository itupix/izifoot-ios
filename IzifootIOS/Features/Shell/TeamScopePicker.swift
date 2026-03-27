import SwiftUI

struct TeamScopePicker: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var teamScopeStore: TeamScopeStore

    var body: some View {
        if canSelectTeam {
            Menu {
                Picker("Equipe active", selection: Binding(
                    get: { teamScopeStore.selectedTeamID ?? "" },
                    set: { newValue in
                        teamScopeStore.selectedTeamID = newValue.isEmpty ? nil : newValue
                    }
                )) {
                    if authStore.me?.role == .direction {
                        Text("Toutes les équipes").tag("")
                    }
                    ForEach(teamScopeStore.teams) { team in
                        Text(team.name).tag(team.id)
                    }
                }
            } label: {
                Label("Equipe", systemImage: "person.3")
            }
        }
    }

    private var canSelectTeam: Bool {
        guard let role = authStore.me?.role else { return false }
        return (role == .direction || role == .coach) && !teamScopeStore.teams.isEmpty
    }
}
