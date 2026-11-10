import SwiftUI

struct AttendanceReportView<Header: View>: View {
    @EnvironmentObject private var teamScopeStore: TeamScopeStore
    @EnvironmentObject private var authStore: AuthStore
    @StateObject private var store = AttendanceReportStore(api: IzifootAPI())
    @State private var mode = Mode.month
    @State private var selectedMonth = ""
    @State private var selectedPlayerID = ""
    @State private var query = ""
    @ViewBuilder var header: () -> Header

    private enum Mode: String, CaseIterable {
        case month = "Par mois", player = "Par joueur"
    }
    private var scope: String {
        "\(authStore.me?.id ?? ""):\(teamScopeStore.selectedTeamID ?? "all"):\(teamScopeStore.scopeRevision)"
    }
    private var visibleReport: AttendanceReport? {
        guard let report = store.report,
              report.teamId == teamScopeStore.selectedTeamID, store.reportScope == scope else { return nil }
        return report
    }

    var body: some View {
        List {
            Section { header() }
                .listRowBackground(Color.clear)
            if teamScopeStore.selectedTeamID == nil {
                Section {
                    Label("Sélectionnez une équipe dans le menu en haut pour consulter ses présences.", systemImage: "person.3")
                        .foregroundStyle(.secondary)
                }
            } else {
                if store.isLoading {
                    Section { ProgressView("Chargement des présences…") }
                } else if let error = store.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.secondary)
                        Button("Réessayer") { Task { await reload() } }
                    }
                } else if let report = visibleReport {
                    reportContent(report)
                }
            }
        }
        .listStyle(.insetGrouped)
        .task(id: scope) { await reload() }
        .refreshable { await reload() }
        .onChange(of: scope) { _ in
            selectedPlayerID = ""
            selectedMonth = ""
            query = ""
        }
    }

    private func reload() async {
        await store.load(teamID: teamScopeStore.selectedTeamID, scope: scope)
        guard let report = visibleReport else { return }
        if !report.months.contains(where: { $0.month == selectedMonth }) {
            selectedMonth = report.defaultMonth()
        }
        if !report.players.contains(where: { $0.id == selectedPlayerID }) {
            selectedPlayerID = ""
        }
    }

    @ViewBuilder private func reportContent(_ report: AttendanceReport) -> some View {
        Section("Présences de la saison") {
            Text("Saison en cours : \(report.season.label) · Effectif actuel").font(.subheadline).foregroundStyle(.secondary)
            metrics(report.summary)
        }
        if report.players.isEmpty {
            Section { Text("Aucun joueur dans l’effectif actuel.").foregroundStyle(.secondary) }
        } else if report.trainings.isEmpty {
            Section { Text("Aucun entraînement pour cette saison.").foregroundStyle(.secondary) }
        } else {
            Section {
                Picker("Détail des présences", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }
            if mode == .month { monthlyContent(report) } else { playerContent(report) }
        }
    }

    @ViewBuilder private func monthlyContent(_ report: AttendanceReport) -> some View {
        Section {
            Picker("Mois", selection: $selectedMonth) {
                ForEach(report.months) { month in
                    Text(AttendanceReport.monthLabel(month.month)).tag(month.month)
                }
            }
            if let month = report.months.first(where: { $0.month == selectedMonth }) { metrics(month.summary) }
        }
        Section("Joueurs × entraînements") {
            AttendanceMonthTable(report: report, month: selectedMonth)
        }
    }

    private func playerContent(_ report: AttendanceReport) -> some View {
        Section("Joueurs") {
            AttendancePlayerSplitView(report: report, selectedPlayerID: $selectedPlayerID, query: $query)
        }
    }

    private func metrics(_ stats: AttendanceReport.Stats) -> some View {
        Text(stats.percentage).font(.title2.bold())
    }

}
