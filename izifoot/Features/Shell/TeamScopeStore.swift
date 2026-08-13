import Combine
import Foundation

struct TeamOption: Identifiable, Hashable {
    let id: String
    let name: String
    let format: String?
}

@MainActor
final class TeamScopeStore: ObservableObject {
    @Published private(set) var selectedTeamID: String?
    @Published private(set) var teams: [TeamOption] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSwitching = false
    @Published private(set) var scopeRevision = 0
    @Published var errorMessage: String?

    private let api: IzifootAPI
    private let defaults = UserDefaults.standard
    private let allTeamsPreferenceValue = "__all__"
    private let preferenceKeyPrefix = "izifoot.team-scope.preference."

    init(api: IzifootAPI = IzifootAPI()) {
        self.api = api
    }

    func bootstrap(authStore: AuthStore) async {
        guard let me = authStore.me else {
            clearScope()
            return
        }

        errorMessage = nil

        if me.role == .player || me.role == .parent {
            let currentTeamID = normalizedTeamID(me.teamId)
            applyTeamOptions(
                currentTeamID.map { [TeamOption(id: $0, name: $0, format: nil)] } ?? [],
                selection: currentTeamID
            )
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await fetchTeamOptions(for: me)
            applyTeamOptions(fetched, selection: resolvedSelection(in: fetched, for: me))
        } catch {
            clearScope()
        }
    }

    func refresh(selecting preferredTeamID: String? = nil, authStore: AuthStore? = nil) async {
        guard let authStore, let me = authStore.me else { return }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        let normalizedPreferredTeamID = normalizedTeamID(preferredTeamID)
        var effectiveMe = me

        if let normalizedPreferredTeamID {
            isSwitching = true
            defer { isSwitching = false }

            do {
                let updatedMe = try await api.updateActiveTeam(teamID: normalizedPreferredTeamID)
                authStore.applyMe(updatedMe)
                persistPreference(normalizedPreferredTeamID, for: updatedMe)
                effectiveMe = updatedMe
                applySelection(normalizedTeamID(updatedMe.teamId))
                scopeRevision += 1
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        do {
            let fetched = try await fetchTeamOptions(for: effectiveMe)
            applyTeamOptions(fetched, selection: resolvedSelection(in: fetched, for: effectiveMe))
        } catch {
            return
        }
    }

    func selectTeam(_ teamID: String?, authStore: AuthStore) async {
        guard let me = authStore.me else { return }

        let requestedTeamID = normalizedTeamID(teamID)
        guard requestedTeamID != selectedTeamID else { return }
        errorMessage = nil

        guard let requestedTeamID else {
            guard me.role == .direction else { return }
            persistPreference(nil, for: me)
            applySelection(nil)
            scopeRevision += 1
            return
        }

        isSwitching = true
        defer { isSwitching = false }

        do {
            let updatedMe = try await api.updateActiveTeam(teamID: requestedTeamID)
            authStore.applyMe(updatedMe)
            persistPreference(requestedTeamID, for: updatedMe)
            applySelection(normalizedTeamID(updatedMe.teamId))
            let fetched = try await fetchTeamOptions(for: updatedMe)
            applyTeamOptions(fetched, selection: resolvedSelection(in: fetched, for: updatedMe))
            scopeRevision += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchTeamOptions(for me: Me) async throws -> [TeamOption] {
        let fetched = try await api.teams().map {
            TeamOption(id: $0.id, name: $0.name, format: $0.format)
        }

        guard me.role == .coach else { return fetched }

        let managedTeamIDs = Set(me.managedTeamIds.compactMap(normalizedTeamID))
        guard !managedTeamIDs.isEmpty else { return [] }
        return fetched.filter { managedTeamIDs.contains($0.id) }
    }

    private func applyTeamOptions(_ fetched: [TeamOption], selection: String?) {
        teams = fetched
        applySelection(selection)
    }

    private func resolvedSelection(in fetched: [TeamOption], for me: Me) -> String? {
        if shouldUseAllTeamsPreference(for: me) {
            return nil
        }

        guard let currentTeamID = normalizedTeamID(me.teamId) else { return nil }
        guard fetched.contains(where: { $0.id == currentTeamID }) else { return nil }
        return currentTeamID
    }

    private func applySelection(_ teamID: String?) {
        selectedTeamID = teamID
        AppSession.shared.activeTeamID = teamID
    }

    private func shouldUseAllTeamsPreference(for me: Me) -> Bool {
        guard me.role == .direction else { return false }
        guard normalizedTeamID(me.teamId) == nil else { return false }
        return defaults.string(forKey: preferenceKey(for: me.id)) == allTeamsPreferenceValue
    }

    private func persistPreference(_ teamID: String?, for me: Me) {
        let key = preferenceKey(for: me.id)

        if me.role == .direction, teamID == nil {
            defaults.set(allTeamsPreferenceValue, forKey: key)
            return
        }

        guard let teamID else {
            defaults.removeObject(forKey: key)
            return
        }

        defaults.set(teamID, forKey: key)
    }

    private func preferenceKey(for userID: String) -> String {
        "\(preferenceKeyPrefix)\(userID)"
    }

    private func normalizedTeamID(_ teamID: String?) -> String? {
        guard let teamID = teamID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !teamID.isEmpty else {
            return nil
        }
        return teamID
    }

    private func clearScope() {
        teams = []
        selectedTeamID = nil
        AppSession.shared.activeTeamID = nil
    }
}
