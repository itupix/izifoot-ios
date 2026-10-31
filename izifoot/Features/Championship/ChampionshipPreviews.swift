#if DEBUG
import SwiftUI

private enum ChampionshipPreviewData {
    static let championship: Championship = {
        let data = """
        {"id":"preview","teamId":"own","seasonId":"season","name":"Championnat départemental U13","status":"DRAFT","doubleRoundRobin":true,"revision":1,"teams":[{"id":"a","name":"Izifoot FC","isOwnTeam":true},{"id":"b","name":"AS Saint-Martin","isOwnTeam":false},{"id":"c","name":"Olympique des Rives","isOwnTeam":false}],"fixtures":[{"id":"f1","round":1,"leg":1,"order":0,"homeTeamId":"a","awayTeamId":"b","kickoffAt":null,"homeScore":null,"awayScore":null,"matchId":null},{"id":"f2","round":2,"leg":1,"order":1,"homeTeamId":"c","awayTeamId":"a","kickoffAt":"2026-11-14T14:00:00Z","homeScore":null,"awayScore":null,"matchId":null},{"id":"f3","round":3,"leg":1,"order":2,"homeTeamId":"b","awayTeamId":"c","kickoffAt":null,"homeScore":2,"awayScore":1,"matchId":null}],"byeRounds":[{"round":1,"teamId":"c"}],"standings":[{"teamId":"b","position":1,"played":1,"won":1,"drawn":0,"lost":0,"goalsFor":2,"goalsAgainst":1,"goalDifference":1,"points":3},{"teamId":"a","position":2,"played":0,"won":0,"drawn":0,"lost":0,"goalsFor":0,"goalsAgainst":0,"goalDifference":0,"points":0},{"teamId":"c","position":3,"played":1,"won":0,"drawn":0,"lost":1,"goalsFor":1,"goalsAgainst":2,"goalDifference":-1,"points":0}]}
        """
        return try! JSONDecoder().decode(Championship.self, from: Data(data.utf8))
    }()
}

struct ChampionshipPreviews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ChampionshipSetupView(ownTeamName: "Izifoot FC", isBusy: false, onGenerate: { _, _, _ in }).navigationTitle("Championnat")
        }.previewDisplayName("Création · Sans compte")
        NavigationStack {
            List { ChampionshipCalendarView(championship: ChampionshipPreviewData.championship, canManage: true, reordering: false, onSelect: { _ in }, onReorder: { _, _ in }, onValidate: {}) }.navigationTitle("Calendrier")
        }.previewDisplayName("Rencontres")
        NavigationStack {
            List { ChampionshipCalendarView(championship: ChampionshipPreviewData.championship, canManage: true, reordering: true, onSelect: { _ in }, onReorder: { _, _ in }, onValidate: {}) }.navigationTitle("Réorganiser")
        }.previewDisplayName("Réorganisation")
        NavigationStack {
            List { ChampionshipStandingsView(championship: ChampionshipPreviewData.championship) }.navigationTitle("Classement")
        }.previewDisplayName("Classement")
    }
}
#endif
