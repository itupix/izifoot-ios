import Foundation

struct TeamOption: Identifiable, Hashable {
    let id: String
    let name: String
    let format: String?
}

@MainActor
final class TeamScopeStore: ObservableObject {
    @Published var selectedTeamID: String?
    @Published private(set) var teams: [TeamOption] = []
    @Published private(set) var isLoading = false

    private let api: IzifootAPI

    init(api: IzifootAPI = IzifootAPI()) {
        self.api = api
    }

    func bootstrap(authStore: AuthStore) async {
        guard let me = authStore.me else {
            teams = []
            selectedTeamID = nil
            AppSession.shared.activeTeamID = nil
            return
        }

        if me.role == .player || me.role == .parent {
            teams = me.teamId.map { [TeamOption(id: $0, name: $0, format: nil)] } ?? []
            selectedTeamID = me.teamId
            AppSession.shared.activeTeamID = me.teamId
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await api.teams().map {
                TeamOption(id: $0.id, name: $0.name, format: $0.format)
            }
            teams = fetched
            if selectedTeamID == nil {
                selectedTeamID = fetched.first?.id
            } else if !fetched.contains(where: { $0.id == selectedTeamID }) {
                selectedTeamID = fetched.first?.id
            }
            AppSession.shared.activeTeamID = selectedTeamID
        } catch {
            teams = []
            selectedTeamID = nil
            AppSession.shared.activeTeamID = nil
        }
    }
}
