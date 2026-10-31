import Foundation

struct ChampionshipEnvelope: Decodable {
    let championship: Championship?
    let canManage: Bool
}
struct Championship: Decodable, Identifiable {
    let id, teamId, seasonId, name, status: String
    let doubleRoundRobin: Bool
    let revision: Int
    let teams: [ChampionshipTeam]
    let fixtures: [ChampionshipFixture]
    let standings: [ChampionshipStanding]
    let byeRounds: [ChampionshipBye]
    var orderedFixtures: [ChampionshipFixture] { fixtures.sorted { $0.order < $1.order } }
    func teamName(_ id: String) -> String { teams.first { $0.id == id }?.name ?? "Équipe" }
    func title(_ fixture: ChampionshipFixture) -> String { "\(teamName(fixture.homeTeamId)) – \(teamName(fixture.awayTeamId))" }
    var ownFixtures: [ChampionshipFixture] {
        let own = teams.first { $0.isOwnTeam }?.id
        return orderedFixtures.filter { $0.homeTeamId == own || $0.awayTeamId == own }
    }
    /// Reordering is restricted to the undated slots, retaining all dated positions.
    func reordered(moving id: String, to target: String) -> [String]? {
        let ordered = orderedFixtures
        guard let source = ordered.firstIndex(where: { $0.id == id }),
              let destination = ordered.firstIndex(where: { $0.id == target }),
              ordered[source].kickoffAt == nil, ordered[destination].kickoffAt == nil else { return nil }
        let slots = ordered.indices.filter { ordered[$0].kickoffAt == nil }
        var movable = slots.map { ordered[$0].id }
        guard let from = movable.firstIndex(of: id), let to = movable.firstIndex(of: target) else { return nil }
        movable.insert(movable.remove(at: from), at: to)
        var result = ordered.map(\.id)
        for (index, slot) in slots.enumerated() { result[slot] = movable[index] }
        return result
    }
}
struct ChampionshipTeam: Decodable, Identifiable { let id, name: String; let isOwnTeam: Bool }
struct ChampionshipFixture: Decodable, Identifiable {
    let id, homeTeamId, awayTeamId: String
    let round, leg, order: Int
    let kickoffAt: String?
    let homeScore, awayScore: Int?
    let matchId: String?
}
struct ChampionshipStanding: Decodable, Identifiable {
    let teamId: String
    let position, played, won, drawn, lost, goalsFor, goalsAgainst, goalDifference, points: Int
    var id: String { teamId }
}
struct ChampionshipBye: Decodable { let round: Int; let teamId: String }
struct ChampionshipCreate: Encodable { let teamId, name: String; let teams: [String]; let doubleRoundRobin: Bool }
struct ChampionshipRevision: Encodable { let revision: Int }
struct ChampionshipOrder: Encodable { let revision: Int; let fixtureIds: [String] }
struct ChampionshipKickoff: Encodable {
    let revision: Int
    let kickoffAt: String?
    enum CodingKeys: String, CodingKey { case revision, kickoffAt }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(revision, forKey: .revision)
        if let kickoffAt { try container.encode(kickoffAt, forKey: .kickoffAt) }
        else { try container.encodeNil(forKey: .kickoffAt) }
    }
}
struct ChampionshipResult: Encodable {
    let revision: Int
    let homeScore, awayScore: Int?
    enum CodingKeys: String, CodingKey { case revision, homeScore, awayScore }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(revision, forKey: .revision)
        try container.encode(homeScore, forKey: .homeScore)
        try container.encode(awayScore, forKey: .awayScore)
    }
}
