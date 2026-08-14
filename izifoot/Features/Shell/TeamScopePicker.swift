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
                        Task {
                            await teamScopeStore.selectTeam(newValue.isEmpty ? nil : newValue, authStore: authStore)
                        }
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
            .disabled(teamScopeStore.isLoading || teamScopeStore.isSwitching)
            .alert("Erreur", isPresented: Binding(
                get: { teamScopeStore.errorMessage != nil },
                set: { _ in teamScopeStore.errorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(teamScopeStore.errorMessage ?? "")
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
        return "Choisir"
    }
}
