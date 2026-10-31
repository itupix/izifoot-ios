import Foundation

@main struct ChampionshipSetupChecks {
    static func main() {
        func error(_ name: String, opponents: [String] = [], excluding: Int? = nil) -> String? {
            ChampionshipNames.error(for: name, ownTeam: "Izifoot FC", opponents: opponents, excluding: excluding)
        }
        precondition(error("") != nil && error(" \n ") != nil)
        precondition(error(" IZIFOOT FC ") != nil)
        precondition(error("Ｉｚｉｆｏｏｔ ＦＣ") != nil)
        precondition(error("Saint Martin", opponents: ["saint martin"]) != nil)
        precondition(error("Étoile", opponents: ["E\u{301}toile"]) != nil)
        precondition(error("Etoile", opponents: ["Étoile"]) == nil, "Accents must remain distinct")
        precondition(error("Renommée", opponents: ["Autre", "Renommée"], excluding: 1) == nil)
        precondition(error("Autre", opponents: ["Autre", "Renommée"], excluding: 1) != nil)
        precondition(error(String(repeating: "a", count: 120)) == nil)
        precondition(error(String(repeating: "a", count: 121)) != nil)
        precondition(error(String(repeating: "🏆", count: 61)) != nil, "UTF16 limit must count multi-unit characters")
        precondition(error("Nouveau", opponents: (0..<31).map { "Équipe \($0)" }) != nil)
        precondition(ChampionshipNames.championshipError(" ") != nil)
        precondition(ChampionshipNames.championshipError(String(repeating: "a", count: 200)) == nil)
        precondition(ChampionshipNames.championshipError(String(repeating: "a", count: 201)) != nil)
        precondition(ChampionshipNames.matchCount(teams: 2, doubleRoundRobin: true) == 2)
        precondition(ChampionshipNames.matchCount(teams: 5, doubleRoundRobin: true) == 20)
        precondition(ChampionshipNames.matchCount(teams: 32, doubleRoundRobin: false) == 496)
        print("PASS: individual names, own-team and NFKC duplicates, preserved accents, rename exclusion, UTF16 limits, participant cap, match count")
    }
}
