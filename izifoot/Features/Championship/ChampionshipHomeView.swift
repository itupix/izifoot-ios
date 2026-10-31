import SwiftUI
import UniformTypeIdentifiers

struct ChampionshipHomeView: View {
    @EnvironmentObject private var scope: TeamScopeStore
    @StateObject private var store = ChampionshipStore()
    @State private var selected = 0
    @State private var name = ""
    @State private var opponents = ""
    @State private var roundTrip = true
    @State private var editing: ChampionshipFixture?
    @State private var editingChampionship: Championship?
    @State private var dragged: String?
    @State private var confirmValidation = false

    var body: some View {
        NavigationStack {
            List {
                Section { TeamScopePicker() }
                if scope.selectedTeamID == nil {
                    Text("Sélectionnez une équipe pour consulter son championnat.")
                } else if let c = store.championship {
                    Section {
                        Text(c.name).font(.headline)
                        Text(c.status == "DRAFT" ? "Brouillon" : "Calendrier validé").foregroundStyle(.secondary)
                        Picker("Vue", selection: $selected) {
                            Text("Calendrier").tag(0)
                            Text("Classement").tag(1)
                        }.pickerStyle(.segmented)
                    }
                    if selected == 0 { calendar(c) } else { standings(c) }
                } else if store.canManage {
                    configuration
                } else if !store.busy {
                    Text("Aucun championnat configuré pour cette équipe.")
                }
                if let error = store.errorMessage {
                    Section { Text(error).foregroundStyle(.red); Button("Réessayer") { Task { await store.load(teamID: scope.selectedTeamID) } } }
                }
                if store.busy { ProgressView() }
            }
            .navigationTitle("Championnat")
            .disabled(store.busy)
            .task(id: "\(scope.selectedTeamID ?? "")-\(scope.scopeRevision)") { await store.load(teamID: scope.selectedTeamID) }
            .onChange(of: scope.selectedTeamID) { _ in
                editing = nil
                editingChampionship = nil
                dragged = nil
                name = ""
                opponents = ""
                roundTrip = true
            }
            .refreshable { await store.load(teamID: scope.selectedTeamID) }
            .sheet(item: $editing) { fixture in
                if let championship = editingChampionship {
                    ChampionshipFixtureEditor(fixture: fixture, championship: championship, store: store)
                }
            }
            .confirmationDialog("Valider le calendrier ?", isPresented: $confirmValidation, titleVisibility: .visible) {
                Button("Valider le calendrier") { Task { await store.validate() } }
            } message: {
                Text("Les rencontres de votre équipe seront ajoutées au planning. Les rencontres sans date resteront dans « À programmer ». Les participants ne pourront plus être modifiés.")
            }
        }
    }

    private var opponentNames: [String] { opponents.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    private var configuration: some View {
        Section("Créer le championnat") {
            Text("Votre équipe (\(scope.teams.first { $0.id == scope.selectedTeamID }?.name ?? "équipe active")) est ajoutée automatiquement. Indiquez uniquement ses adversaires (1 à 31).")
            TextField("Nom du championnat", text: $name)
            TextField("Adversaires, un par ligne", text: $opponents, axis: .vertical).lineLimit(3...12)
            Toggle("Matchs aller-retour", isOn: $roundTrip)
            Text("Les journées et les éventuels repos seront générés automatiquement. Les dates et heures pourront être renseignées ensuite.").font(.footnote).foregroundStyle(.secondary)
            Button("Créer le calendrier") { Task { await store.create(name: name.trimmingCharacters(in: .whitespacesAndNewlines), opponents: opponentNames, doubleRoundRobin: roundTrip) } }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(1...31).contains(opponentNames.count))
        }
    }
    @ViewBuilder private func calendar(_ c: Championship) -> some View {
        if store.canManage {
            Section {
                Text("Glissez les rencontres sans date pour modifier leur ordre. Les créneaux datés restent fixes. Vous pouvez aussi utiliser Monter et Descendre.").font(.footnote)
                if c.status == "DRAFT" { Button("Valider le calendrier") { confirmValidation = true } }
            }
        }
        Section("Rencontres") {
            ForEach(c.orderedFixtures) { fixture in
                fixtureRow(fixture, championship: c)
            }
        }
        if !c.byeRounds.isEmpty {
            Section("Repos") {
                ForEach(Array(c.byeRounds.enumerated()), id: \.offset) { _, bye in
                    Label("Journée \(bye.round) • \(c.teamName(bye.teamId)) : repos", systemImage: "pause.circle").foregroundStyle(.secondary)
                }
            }
        }
    }
    private func fixtureRow(_ fixture: ChampionshipFixture, championship c: Championship) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(c.title(fixture)).font(.headline)
            Text(fixture.kickoffAt.map(DateFormatters.display) ?? "À programmer").foregroundStyle(.secondary)
            Text("Journée \(fixture.round) • \(fixture.leg == 1 ? "Aller" : "Retour")").font(.caption)
            if let home = fixture.homeScore, let away = fixture.awayScore { Text("\(home) – \(away)").bold() }
            if store.canManage {
                Button("Date, heure et résultat") { editingChampionship = c; editing = fixture }
                if fixture.kickoffAt == nil {
                    HStack {
                        Button("Monter") { move(fixture, in: c, offset: -1) }.disabled(neighbor(fixture, in: c, offset: -1) == nil)
                        Button("Descendre") { move(fixture, in: c, offset: 1) }.disabled(neighbor(fixture, in: c, offset: 1) == nil)
                    }.buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
        .onDrag {
            guard store.canManage, fixture.kickoffAt == nil else { return NSItemProvider() }
            dragged = fixture.id
            return NSItemProvider(object: fixture.id as NSString)
        }
        .onDrop(of: [UTType.text], isTargeted: nil) { _ in
            guard store.canManage, let dragged, fixture.kickoffAt == nil else { return false }
            Task { await store.reorder(dragged, to: fixture.id) }
            self.dragged = nil
            return true
        }
    }
    private func neighbor(_ fixture: ChampionshipFixture, in c: Championship, offset: Int) -> String? {
        let ids = c.orderedFixtures.filter { $0.kickoffAt == nil }.map(\.id)
        guard let index = ids.firstIndex(of: fixture.id), ids.indices.contains(index + offset) else { return nil }
        return ids[index + offset]
    }
    private func move(_ fixture: ChampionshipFixture, in c: Championship, offset: Int) {
        guard let target = neighbor(fixture, in: c, offset: offset) else { return }
        Task { await store.reorder(fixture.id, to: target) }
    }
    private func standings(_ c: Championship) -> some View {
        Section {
            Text("Classement indicatif • Victoire 3 pts, nul 1 pt, défaite 0 pt. Départage : points, différence de buts, buts marqués, nom.").font(.footnote)
            ForEach(c.standings.sorted { $0.position < $1.position }) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("\(row.position). \(c.teamName(row.teamId))").bold(); Spacer(); Text("\(row.points) pts").bold() }
                    Text("J \(row.played) · V \(row.won) · N \(row.drawn) · D \(row.lost) · BP \(row.goalsFor) · BC \(row.goalsAgainst) · Diff \(row.goalDifference)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ChampionshipFixtureEditor: View {
    @Environment(\.dismiss) private var dismiss
    let fixture: ChampionshipFixture
    let championship: Championship
    @ObservedObject var store: ChampionshipStore
    @State private var scheduled = false
    @State private var date = Date()
    @State private var home = ""
    @State private var away = ""
    private var validScores: Bool { (home.isEmpty && away.isEmpty) || ((0...999).contains(Int(home) ?? -1) && (0...999).contains(Int(away) ?? -1)) }
    var body: some View {
        NavigationStack {
            Form {
                Section(championship.title(fixture)) {
                    Toggle("Date et heure définies", isOn: $scheduled)
                    if scheduled { DatePicker("Coup d’envoi", selection: $date, displayedComponents: [.date, .hourAndMinute]) }
                    Button("Enregistrer la programmation") {
                        Task { await store.schedule(fixture, date: scheduled ? date : nil); if store.errorMessage == nil { dismiss() } }
                    }
                }
                if championship.status == "VALIDATED" {
                    Section("Résultat") {
                        TextField(championship.teamName(fixture.homeTeamId), text: $home).keyboardType(.numberPad)
                        TextField(championship.teamName(fixture.awayTeamId), text: $away).keyboardType(.numberPad)
                        Text("Laissez les deux scores vides pour effacer le résultat.").font(.footnote)
                        Button("Enregistrer le résultat") { Task { await store.result(fixture, home: Int(home), away: Int(away)); if store.errorMessage == nil { dismiss() } } }.disabled(!validScores)
                    }
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .disabled(store.busy)
            .navigationTitle("Rencontre")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .onAppear {
                scheduled = fixture.kickoffAt != nil
                date = fixture.kickoffAt.flatMap(DateFormatters.parseISODate) ?? Date()
                home = fixture.homeScore.map(String.init) ?? ""
                away = fixture.awayScore.map(String.init) ?? ""
            }
        }
    }
}

/// Planning shows only this team's validated fixtures, retaining nil dates as unscheduled.
struct ChampionshipPlanningSection: View {
    @EnvironmentObject private var scope: TeamScopeStore
    @ObservedObject var store: ChampionshipStore
    let selectedDate: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let c = store.championship, c.status == "VALIDATED" {
                let dated = c.ownFixtures.filter { fixture in
                    guard let raw = fixture.kickoffAt, let date = DateFormatters.parseISODate(raw) else { return false }
                    return Calendar.current.isDate(date, inSameDayAs: selectedDate)
                }
                let unscheduled = c.ownFixtures.filter { $0.kickoffAt == nil }
                if !dated.isEmpty {
                    Text("Championnat").font(.headline)
                    ForEach(dated) { fixture in
                        NavigationLink { ChampionshipHomeView() } label: {
                            VStack(alignment: .leading) { Text(c.title(fixture)); Text(fixture.kickoffAt.map(DateFormatters.display) ?? "").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                if !unscheduled.isEmpty {
                    Text("À programmer").font(.headline)
                    ForEach(unscheduled) { fixture in
                        NavigationLink { ChampionshipHomeView() } label: {
                            VStack(alignment: .leading) { Text(c.title(fixture)); Text("Journée \(fixture.round) • Championnat").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .task(id: "\(scope.selectedTeamID ?? "")-\(scope.scopeRevision)") { await store.load(teamID: scope.selectedTeamID) }
        .onAppear { Task { await store.load(teamID: scope.selectedTeamID) } }
    }
}
