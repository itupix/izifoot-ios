import Foundation

@main struct ChampionshipChecks {
    static func main() throws {
        let fixtureJSON = """
        {"id":"league","teamId":"own","seasonId":"season","name":"Ligue","doubleRoundRobin":true,"status":"VALIDATED","revision":3,"teams":[{"id":"a","name":"Nous","isOwnTeam":true},{"id":"b","name":"Autres","isOwnTeam":false},{"id":"c","name":"Troisième","isOwnTeam":false}],"fixtures":[{"id":"one","homeTeamId":"a","awayTeamId":"b","round":1,"leg":1,"order":0,"kickoffAt":null,"homeScore":null,"awayScore":null,"matchId":"m1"},{"id":"fixed","homeTeamId":"b","awayTeamId":"c","round":1,"leg":1,"order":1,"kickoffAt":"2026-11-01T15:00:00Z","homeScore":2,"awayScore":1,"matchId":null},{"id":"three","homeTeamId":"b","awayTeamId":"a","round":2,"leg":2,"order":2,"kickoffAt":null,"homeScore":null,"awayScore":null,"matchId":"m2"}],"standings":[],"byeRounds":[]}
        """
        let c = try JSONDecoder().decode(Championship.self, from: Data(fixtureJSON.utf8))
        precondition(c.ownFixtures.map(\.id) == ["one", "three"])
        precondition(c.reordered(moving: "one", to: "three") == ["three", "fixed", "one"])
        precondition(c.reordered(moving: "fixed", to: "three") == nil)
        precondition(c.reordered(moving: "one", to: "fixed") == nil)
        precondition(c.fixtures[0].kickoffAt == nil)
        let payload = try JSONEncoder().encode(ChampionshipKickoff(revision: 3, kickoffAt: nil))
        let object = try JSONSerialization.jsonObject(with: payload) as! [String: Any]
        precondition(object["kickoffAt"] is NSNull)
        let scores = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ChampionshipResult(revision: 3, homeScore: nil, awayScore: nil))) as! [String: Any]
        precondition(scores["homeScore"] is NSNull && scores["awayScore"] is NSNull)
        print("PASS: contract decoding, own-team planning, null schedule, fixed dated slots, reorder rejection, explicit null result reset")
    }
}
