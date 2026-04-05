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
                HStack(spacing: 6) {
                    Text(selectedTeamLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: 180)
            }
        }
    }

    private var canSelectTeam: Bool {
        guard let role = authStore.me?.role else { return false }
        return (role == .direction || role == .coach) && !teamScopeStore.teams.isEmpty
    }

    private var selectedTeamLabel: String {
        if let selectedTeamID = teamScopeStore.selectedTeamID,
           let selectedTeam = teamScopeStore.teams.first(where: { $0.id == selectedTeamID }) {
            return selectedTeam.name
        }
        if authStore.me?.role == .direction {
            return "Toutes"
        }
        return teamScopeStore.teams.first?.name ?? "Equipe"
    }
}
