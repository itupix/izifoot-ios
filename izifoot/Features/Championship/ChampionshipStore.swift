import Combine
import Foundation

@MainActor
final class ChampionshipStore: ObservableObject {
    @Published private(set) var championship: Championship?
    @Published private(set) var canManage = false
    @Published private(set) var busy = false
    @Published var errorMessage: String?
    private var generation = 0
    private var teamID: String?
    private let client = APIClient.shared

    func load(teamID: String?) async {
        generation += 1
        let requestGeneration = generation
        self.teamID = teamID
        championship = nil
        canManage = false
        errorMessage = nil
        busy = false
        guard let teamID else { return }
        var query = URLComponents()
        query.path = "/championship"
        query.queryItems = [URLQueryItem(name: "teamId", value: teamID)]
        busy = true
        defer { if generation == requestGeneration { busy = false } }
        do {
            let response = try await client.get(query.string!, responseType: ChampionshipEnvelope.self)
            guard generation == requestGeneration else { return }
            championship = response.championship
            canManage = response.canManage
        } catch {
            guard generation == requestGeneration, !error.isCancellationError else { return }
            errorMessage = error.localizedDescription
        }
    }
    func create(name: String, opponents: [String], doubleRoundRobin: Bool) async {
        guard let teamID else { return }
        await perform { try await self.client.post("/championship", body: ChampionshipCreate(teamId: teamID, name: name, teams: opponents, doubleRoundRobin: doubleRoundRobin), responseType: ChampionshipEnvelope.self) }
    }
    func schedule(_ fixture: ChampionshipFixture, date: Date?) async {
        guard let c = championship else { return }
        await perform { try await self.client.patch("/championship/\(c.id)/fixtures/\(fixture.id)", body: ChampionshipKickoff(revision: c.revision, kickoffAt: date.map(DateFormatters.isoString)), responseType: ChampionshipEnvelope.self) }
    }
    func reorder(_ id: String, to target: String) async {
        guard let c = championship, let ids = c.reordered(moving: id, to: target) else { return }
        await perform { try await self.client.put("/championship/\(c.id)/order", body: ChampionshipOrder(revision: c.revision, fixtureIds: ids), responseType: ChampionshipEnvelope.self) }
    }
    func validate() async {
        guard let c = championship else { return }
        await perform { try await self.client.post("/championship/\(c.id)/validate", body: ChampionshipRevision(revision: c.revision), responseType: ChampionshipEnvelope.self) }
    }
    func result(_ fixture: ChampionshipFixture, home: Int?, away: Int?) async {
        guard let c = championship else { return }
        await perform { try await self.client.put("/championship/\(c.id)/fixtures/\(fixture.id)/result", body: ChampionshipResult(revision: c.revision, homeScore: home, awayScore: away), responseType: ChampionshipEnvelope.self) }
    }
    private func perform(_ operation: () async throws -> ChampionshipEnvelope) async {
        guard !busy else { return }
        let requestGeneration = generation
        busy = true
        defer { if generation == requestGeneration { busy = false } }
        do {
            let response = try await operation()
            guard generation == requestGeneration else { return }
            championship = response.championship
            canManage = response.canManage
            errorMessage = nil
        } catch {
            guard generation == requestGeneration, !error.isCancellationError else { return }
            if case APIError.server(status: 409, message: _) = error {
                // Refresh the revision after a concurrent edit; the user can retry explicitly.
                if let teamID {
                    var query = URLComponents()
                    query.path = "/championship"
                    query.queryItems = [URLQueryItem(name: "teamId", value: teamID)]
                    if let response = try? await client.get(query.string!, responseType: ChampionshipEnvelope.self) {
                        guard generation == requestGeneration else { return }
                        championship = response.championship
                        canManage = response.canManage
                    }
                }
                errorMessage = "Le championnat a changé. Les données ont été actualisées ; réessayez votre modification."
            } else { errorMessage = error.localizedDescription }
        }
    }
}
