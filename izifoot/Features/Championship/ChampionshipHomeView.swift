import SwiftUI
import UniformTypeIdentifiers

struct ChampionshipHomeView: View {
    @EnvironmentObject private var scope: TeamScopeStore
    @StateObject private var store = ChampionshipStore()
    @State private var selected = 0
    @State private var editorAction = 0
    @State private var choosingAction = false
    @State private var pendingFixture: ChampionshipFixture?
    @State private var editing: ChampionshipFixture?
    @State private var editingChampionship: Championship?
    @State private var reordering = false
    @State private var dragged: String?
    @State private var confirmValidation = false

    var body: some View {
        NavigationStack {
            Group {
            if scope.selectedTeamID != nil && store.canManage && store.championship == nil {
                ChampionshipSetupView(ownTeamName: ownTeamName, isBusy: store.busy, errorMessage: store.errorMessage, showTeamPicker: true) { name, teams, roundTrip in Task { await store.create(name: name, opponents: teams, doubleRoundRobin: roundTrip) } }.id(scope.selectedTeamID)
            } else {
            List {
                Section { TeamScopePicker() }
                if scope.selectedTeamID == nil {
                    ContentUnavailableChampionship(message: "Sélectionnez une équipe pour consulter son championnat.")
                } else if let c = store.championship {
                    Section {
                        Text(c.name).font(.title2.bold())
                        Text(c.status == "DRAFT" ? "Brouillon · Organisez vos rencontres" : "Calendrier validé").font(.subheadline).foregroundStyle(.secondary)
                        Picker("Vue", selection: $selected) {
                            Text("Calendrier").tag(0)
                            Text("Classement").tag(1)
                        }.pickerStyle(.segmented)
                    }
                    if selected == 0 {
                        ChampionshipCalendarView(championship: c, canManage: store.canManage, reordering: reordering, onSelect: { fixture in editingChampionship = c; pendingFixture = fixture; choosingAction = true }, onReorder: { source, target in Task { await store.reorder(source, to: target) } }, onValidate: { confirmValidation = true })
                    } else { ChampionshipStandingsView(championship: c) }
                } else if !store.busy {
                    ContentUnavailableChampionship(message: "Aucun championnat pour le moment. Votre encadrant peut le créer pour votre équipe.")
                }
                if let error = store.errorMessage {
                    Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red); Button("Actualiser") { Task { await store.load(teamID: scope.selectedTeamID) } } }
                }
                if store.busy { ProgressView("Chargement…") }
            }
            }
            }
            .navigationTitle("Championnat")
            .scrollDismissesKeyboard(.interactively)
            .disabled(store.busy)
            .toolbar {
                if store.canManage, store.championship != nil, selected == 0 {
                    ToolbarItem(placement: .primaryAction) { Button(reordering ? "Terminer" : "Réorganiser") { reordering.toggle() } }
                }
            }
            .task(id: "\(scope.selectedTeamID ?? "")-\(scope.scopeRevision)") { await store.load(teamID: scope.selectedTeamID) }
            .onChange(of: scope.selectedTeamID) { _ in editing = nil; pendingFixture = nil; choosingAction = false; editingChampionship = nil; reordering = false; dragged = nil; selected = 0 }
            .onChange(of: selected) { _ in reordering = false; dragged = nil }
            .refreshable { await store.load(teamID: scope.selectedTeamID) }
            .sheet(item: $editing) { fixture in
                if let championship = editingChampionship { ChampionshipFixtureEditor(fixture: fixture, championship: championship, store: store, action: editorAction) }
            }
            .confirmationDialog("Modifier la rencontre", isPresented: $choosingAction, titleVisibility: .visible) {
                Button(pendingFixture?.kickoffAt == nil ? "Programmer la rencontre" : "Modifier l’horaire") { editorAction = 0; editing = pendingFixture }
                if editingChampionship?.status == "VALIDATED" {
                    Button(pendingFixture?.homeScore == nil ? "Saisir le résultat" : "Modifier le résultat") { editorAction = 1; editing = pendingFixture }
                }
                Button("Annuler", role: .cancel) {}
            }
            .confirmationDialog("Valider le calendrier ?", isPresented: $confirmValidation, titleVisibility: .visible) {
                Button("Valider le calendrier") { Task { await store.validate() } }
            } message: { Text("Les rencontres de votre équipe seront ajoutées au planning. Les rencontres sans date resteront dans « À programmer ». Vous pourrez ajouter leurs horaires plus tard.") }
        }
    }
    private var ownTeamName: String { scope.teams.first { $0.id == scope.selectedTeamID }?.name ?? "Votre équipe" }
}

private struct ContentUnavailableChampionship: View {
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy").font(.largeTitle).foregroundStyle(.secondary)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}

struct ChampionshipCalendarView: View {
    let championship: Championship
    let canManage: Bool
    let reordering: Bool
    let onSelect: (ChampionshipFixture) -> Void
    let onReorder: (String, String) -> Void
    let onValidate: () -> Void
    @State private var dragged: String?
    @State private var showByes = false
    var body: some View {
        Section {
            let unscheduled = championship.fixtures.filter { $0.kickoffAt == nil }.count
            Text("\(championship.fixtures.count) rencontres · \(unscheduled) à programmer").font(.subheadline).foregroundStyle(.secondary)
            if reordering {
                Label("Déplacez les rencontres sans date. Les positions des rencontres déjà datées restent fixes.", systemImage: "hand.draw").font(.footnote)
            }
            if canManage && championship.status == "DRAFT" && !reordering {
                Button(action: onValidate) { Label("Valider le calendrier", systemImage: "checkmark.circle").frame(minHeight: 44) }.buttonStyle(.borderedProminent)
                Text("Les horaires sont facultatifs : vous pourrez les ajouter plus tard.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        Section("Rencontres") {
            ForEach(championship.orderedFixtures) { fixture in
                VStack(alignment: .leading, spacing: 10) {
                    if canManage && !reordering {
                        Button { onSelect(fixture) } label: { ChampionshipFixtureCard(fixture: fixture, championship: championship, showsChevron: true) }.buttonStyle(.plain)
                    } else { ChampionshipFixtureCard(fixture: fixture, championship: championship, showsChevron: false) }
                    if canManage && reordering {
                        if fixture.kickoffAt == nil {
                            HStack(spacing: 16) {
                                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).accessibilityLabel("Rencontre déplaçable")
                                Button { move(fixture, offset: -1) } label: { Label("Monter", systemImage: "arrow.up").frame(minHeight: 44) }.disabled(neighbor(fixture, offset: -1) == nil)
                                Button { move(fixture, offset: 1) } label: { Label("Descendre", systemImage: "arrow.down").frame(minHeight: 44) }.disabled(neighbor(fixture, offset: 1) == nil)
                            }.font(.subheadline).buttonStyle(.borderless)
                        } else { Label("Position fixe · horaire défini", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .padding(.vertical, 6)
                .onDrag {
                    guard canManage, reordering, fixture.kickoffAt == nil else { return NSItemProvider() }
                    dragged = fixture.id
                    return NSItemProvider(object: fixture.id as NSString)
                }
                .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                    guard canManage, reordering, let dragged, fixture.kickoffAt == nil else { return false }
                    onReorder(dragged, fixture.id); self.dragged = nil; return true
                }
            }
        }
        if !championship.byeRounds.isEmpty {
            Section {
                DisclosureGroup("Repos par journée", isExpanded: $showByes) {
                    ForEach(Array(championship.byeRounds.enumerated()), id: \.offset) { _, bye in
                        Label("Journée \(bye.round) · \(championship.teamName(bye.teamId))", systemImage: "pause.circle").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private func neighbor(_ fixture: ChampionshipFixture, offset: Int) -> String? {
        let ids = championship.orderedFixtures.filter { $0.kickoffAt == nil }.map(\.id)
        guard let index = ids.firstIndex(of: fixture.id), ids.indices.contains(index + offset) else { return nil }
        return ids[index + offset]
    }
    private func move(_ fixture: ChampionshipFixture, offset: Int) { if let target = neighbor(fixture, offset: offset) { onReorder(fixture.id, target) } }
}

private struct ChampionshipFixtureCard: View {
    let fixture: ChampionshipFixture
    let championship: Championship
    let showsChevron: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Journée \(fixture.round) · \(fixture.leg == 1 ? "Aller" : "Retour")").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if showsChevron { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
            }
            teamLine(fixture.homeTeamId, venue: "Domicile", score: fixture.homeScore)
            teamLine(fixture.awayTeamId, venue: "Extérieur", score: fixture.awayScore)
            HStack {
                Label(fixture.kickoffAt.map(DateFormatters.display) ?? "À programmer", systemImage: fixture.kickoffAt == nil ? "calendar.badge.clock" : "calendar").font(.subheadline).foregroundStyle(fixture.kickoffAt == nil ? Color.secondary : Color.primary)
                Spacer(minLength: 8)
                if fixture.homeScore == nil { Text("À jouer").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    private func teamLine(_ id: String, venue: String, score: Int?) -> some View {
        let own = championship.teams.first { $0.id == id }?.isOwnTeam == true
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if own { Image(systemName: "person.fill.checkmark").font(.caption).foregroundStyle(Color.accentColor) }
                    Text(championship.teamName(id)).fontWeight(own ? .bold : .medium).foregroundStyle(.primary)
                }
                Text(own ? "\(venue) · Votre équipe" : venue).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let score { Text("\(score)").font(.title3.monospacedDigit().bold()).foregroundStyle(.primary) }
        }
    }
}

struct ChampionshipStandingsView: View {
    let championship: Championship
    var body: some View {
        Section {
            Text("Classement indicatif").font(.subheadline).foregroundStyle(.secondary)
            if championship.standings.allSatisfy({ $0.played == 0 }) {
                Text("Aucun résultat enregistré. Le classement évoluera après les premières rencontres.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(championship.standings.sorted { $0.position < $1.position }) { row in
                DisclosureGroup {
                    Text("Victoires \(row.won) · Nuls \(row.drawn) · Défaites \(row.lost)").font(.subheadline)
                    Text("Buts marqués \(row.goalsFor) · Buts encaissés \(row.goalsAgainst)").font(.subheadline)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(row.position)").font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(championship.teamName(row.teamId)).font(.headline)
                            if championship.teams.first(where: { $0.id == row.teamId })?.isOwnTeam == true {
                                Label("Votre équipe", systemImage: "person.fill.checkmark").font(.caption).foregroundStyle(Color.accentColor)
                            }
                            Text("\(row.played) joués · Diff. \(row.goalDifference > 0 ? "+" : "")\(row.goalDifference)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text("\(row.points) pts").font(.headline.monospacedDigit())
                    }.padding(.vertical, 4)
                }
            }
        }
        Section {
            DisclosureGroup("Règles du classement") {
                Text("Victoire : 3 points. Nul : 1 point. Défaite : 0 point.")
                Text("Départage : points, différence de buts, buts marqués, puis nom de l’équipe.")
            }.font(.subheadline)
        }
    }
}

private struct ChampionshipFixtureEditor: View {
    @Environment(\.dismiss) private var dismiss
    let fixture: ChampionshipFixture
    let championship: Championship
    @ObservedObject var store: ChampionshipStore
    let action: Int
    @State private var confirmRemoval = false
    @State private var scheduled = false
    @State private var date = Date()
    @State private var home = ""
    @State private var away = ""
    @FocusState private var scoreFocused: Bool
    private var validScores: Bool { (home.isEmpty && away.isEmpty) || ((0...999).contains(Int(home) ?? -1) && (0...999).contains(Int(away) ?? -1)) }
    var body: some View {
        NavigationStack {
            Form {
                Section { ChampionshipFixtureCard(fixture: fixture, championship: championship, showsChevron: false) }
                if action == 0 {
                    Section {
                        Toggle("Définir une date et une heure", isOn: $scheduled).frame(minHeight: 44)
                        if scheduled { DatePicker("Coup d’envoi", selection: $date, displayedComponents: [.date, .hourAndMinute]) }
                        if fixture.kickoffAt != nil { Button("Retirer l’horaire", role: .destructive) { confirmRemoval = true }.frame(minHeight: 44) }
                    } header: { Text(fixture.kickoffAt == nil ? "Programmer la rencontre" : "Modifier l’horaire") } footer: { Text(scheduled ? (isOwnFixture ? "La rencontre apparaîtra à cette date dans le planning de votre équipe." : "L’horaire sera affiché dans le calendrier du championnat.") : (isOwnFixture ? "La rencontre restera dans « À programmer »." : "La rencontre restera sans horaire dans le calendrier du championnat.")) }
                } else {
                    Section {
                        scoreField(championship.teamName(fixture.homeTeamId), value: $home)
                        scoreField(championship.teamName(fixture.awayTeamId), value: $away)
                        if fixture.homeScore != nil { Button("Effacer le résultat", role: .destructive) { confirmRemoval = true }.frame(minHeight: 44) }
                        if !validScores { Text("Renseignez les deux scores entre 0 et 999, ou laissez-les tous les deux vides.").font(.footnote).foregroundStyle(.red) }
                    } header: { Text(fixture.homeScore == nil ? "Saisir le résultat" : "Modifier le résultat") } footer: { Text("Pour retirer un résultat, effacez les deux scores. Le classement sera actualisé après l’enregistrement.") }
                }
                if let error = store.errorMessage { Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) } }
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(store.busy)
            .navigationTitle("Rencontre")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    scoreFocused = false
                    Task {
                        if action == 0 { await store.schedule(fixture, date: scheduled ? date : nil) }
                        else { await store.result(fixture, home: Int(home), away: Int(away)) }
                        if store.errorMessage == nil { dismiss() }
                    }
                } label: { HStack { Spacer(); if store.busy { ProgressView() }; Text(action == 0 ? "Enregistrer l’horaire" : "Enregistrer le résultat").bold(); Spacer() }.frame(minHeight: 44) }
                    .buttonStyle(.borderedProminent).disabled(store.busy || (action == 1 && !validScores)).padding().background(.bar)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }; ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Terminer") { scoreFocused = false } } }
            .confirmationDialog(action == 0 ? "Retirer l’horaire ?" : "Effacer le résultat ?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                Button(action == 0 ? "Retirer l’horaire" : "Effacer le résultat", role: .destructive) {
                    scoreFocused = false
                    Task {
                        if action == 0 { await store.schedule(fixture, date: nil) }
                        else { await store.result(fixture, home: nil, away: nil) }
                        if store.errorMessage == nil { dismiss() }
                    }
                }
            } message: { Text(action == 0 ? "La rencontre restera dans le championnat sans date ni heure." : "Les scores seront retirés et le classement sera recalculé.") }
            .onAppear {
                scheduled = fixture.kickoffAt != nil
                date = fixture.kickoffAt.flatMap(DateFormatters.parseISODate) ?? Date()
                home = fixture.homeScore.map(String.init) ?? ""
                away = fixture.awayScore.map(String.init) ?? ""
            }
        }
    }
    private var isOwnFixture: Bool { championship.ownFixtures.contains { $0.id == fixture.id } }
    private func scoreField(_ title: String, value: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("Score", text: value).keyboardType(.numberPad).focused($scoreFocused).multilineTextAlignment(.trailing).frame(width: 72).accessibilityLabel("Score de \(title)")
        }.frame(minHeight: 44)
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
