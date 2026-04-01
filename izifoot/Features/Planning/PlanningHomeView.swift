import Combine
import SwiftUI

@MainActor
final class PlanningHomeViewModel: ObservableObject {
    @Published private(set) var trainings: [Training] = []
    @Published private(set) var matchdays: [Matchday] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI? = nil) {
        self.api = api ?? IzifootAPI()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let trainingsTask = api.allTrainings()
            async let matchdaysTask = api.allMatchdays()
            trainings = try await trainingsTask.sorted { $0.date > $1.date }
            matchdays = try await matchdaysTask.sorted { $0.date > $1.date }
            errorMessage = nil
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func createTraining(date: Date, teamID: String?, teamName: String?) async {
        do {
            let newTraining = try await api.createTraining(
                dateISO8601: DateFormatters.isoString(from: date),
                teamID: teamID,
                teamName: teamName
            )
            trainings.insert(newTraining, at: 0)
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }

    func createMatchday(
        date: Date,
        location: String,
        teamID: String?,
        teamName: String?,
        startTime: String? = nil,
        meetingTime: String? = nil
    ) async {
        do {
            let newMatchday = try await api.createMatchday(
                dateISO8601: DateFormatters.isoString(from: date),
                lieu: location,
                teamID: teamID,
                teamName: teamName,
                startTime: startTime,
                meetingTime: meetingTime
            )
            matchdays.insert(newMatchday, at: 0)
        } catch {
            if !error.isCancellationError { errorMessage = error.localizedDescription }
        }
    }
}

struct PlanningHomeView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var teamScopeStore: TeamScopeStore

    @AppStorage("izifoot.planning.lastDate") private var storedPlanningDate = ""

    @StateObject private var viewModel = PlanningHomeViewModel()
    @State private var selectedDate = PlanningDateHelpers.defaultSelectedDate(storedValue: nil)
    @State private var isDatePickerPresented = false
    @State private var isPlateauSheetPresented = false
    @State private var plateauLocation = ""
    @State private var updatingTrainingIntentIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    dateHeader

                    PlanningSectionCard(title: "Entraînements") {
                        if writable && requiresSelection && teamScopeStore.selectedTeamID == nil {
                            Text("Sélectionnez une équipe active pour modifier les données.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if dayTrainings.isEmpty {
                            Text("Aucun entraînement ce jour.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(dayTrainings) { training in
                                if writable {
                                    NavigationLink {
                                        TrainingDetailView(training: training)
                                    } label: {
                                        PlanningEventRow(
                                            title: "Entraînement",
                                            subtitle: trainingSubtitle(for: training),
                                            systemImage: training.status == "CANCELLED" ? "xmark.circle.fill" : "soccerball",
                                            tint: training.status == "CANCELLED" ? .red : .accentColor
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    PlanningEventRow(
                                        title: "Entraînement",
                                        subtitle: trainingSubtitle(for: training),
                                        systemImage: training.status == "CANCELLED" ? "xmark.circle.fill" : "soccerball",
                                        tint: training.status == "CANCELLED" ? .red : .accentColor
                                    )
                                }

                                if isReadOnlyRole, training.canSetTrainingIntent == true {
                                    HStack(spacing: 8) {
                                        Button {
                                            Task { await setTrainingIntent(trainingID: training.id, present: true) }
                                        } label: {
                                            Text("Présent")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(training.myTrainingIntent == "PRESENT" ? .green : .accentColor)
                                        .disabled(updatingTrainingIntentIDs.contains(training.id))

                                        Button {
                                            Task { await setTrainingIntent(trainingID: training.id, present: false) }
                                        } label: {
                                            Text("Absent")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(training.myTrainingIntent == "ABSENT" ? .red : .secondary)
                                        .disabled(updatingTrainingIntentIDs.contains(training.id))
                                    }
                                }
                            }
                        }

                        if teamScopedWritable {
                            Button("Ajouter un entraînement") {
                                Task {
                                    await viewModel.createTraining(
                                        date: selectedDate,
                                        teamID: teamScopeStore.selectedTeamID,
                                        teamName: selectedTeamName
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    PlanningSectionCard(title: "Plateaux") {
                        if dayMatchdays.isEmpty {
                            Text("Aucun plateau ce jour.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(dayMatchdays) { matchday in
                                if writable {
                                    NavigationLink {
                                        MatchdayDetailView(matchday: matchday)
                                    } label: {
                                        PlanningEventRow(
                                            title: "Plateau — \(matchday.lieu ?? "Lieu non renseigné")",
                                            subtitle: teamSubtitle(for: matchday.teamId),
                                            systemImage: "trophy",
                                            tint: .orange
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    PlanningEventRow(
                                        title: "Plateau — \(matchday.lieu ?? "Lieu non renseigné")",
                                        subtitle: teamSubtitle(for: matchday.teamId),
                                        systemImage: "trophy",
                                        tint: .orange
                                    )
                                }
                            }
                        }

                        if teamScopedWritable {
                            Button("Ajouter un plateau") {
                                plateauLocation = ""
                                isPlateauSheetPresented = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .navigationTitle("Planning")
            .appChrome()
            .toolbar {
                if viewModel.isLoading {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .refreshable {
                await viewModel.load()
            }
            .task {
                selectedDate = PlanningDateHelpers.defaultSelectedDate(storedValue: storedPlanningDate)
                await viewModel.load()
            }
            .onChange(of: selectedDate) { _, newValue in
                storedPlanningDate = PlanningDateHelpers.storageKey(for: newValue)
            }
            .sheet(isPresented: $isDatePickerPresented) {
                PlanningDatePickerSheet(
                    selectedDate: $selectedDate,
                    trainingDayKeys: trainingDayKeys,
                    matchdayDayKeys: matchdayDayKeys
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $isPlateauSheetPresented) {
                CreatePlateauSheet(
                    selectedDate: selectedDate,
                    location: $plateauLocation,
                    suggestedLocations: matchdayLocations
                ) {
                    await viewModel.createMatchday(
                        date: selectedDate,
                        location: plateauLocation.trimmingCharacters(in: .whitespacesAndNewlines),
                        teamID: teamScopeStore.selectedTeamID,
                        teamName: selectedTeamName
                    )
                    plateauLocation = ""
                    isPlateauSheetPresented = false
                }
                .presentationDetents([.medium, .large])
            }
            .alert("Erreur", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { _ in viewModel.errorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var dateHeader: some View {
        HStack(spacing: 12) {
            Button {
                selectedDate = PlanningDateHelpers.addDays(-1, to: selectedDate)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)

            Button {
                selectedDate = PlanningDateHelpers.today
            } label: {
                VStack(spacing: 2) {
                    Text(isTodaySelected ? "Aujourd'hui" : PlanningDateHelpers.title(for: selectedDate))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if !isTodaySelected {
                        Text("Revenir à aujourd'hui")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    selectedDate = PlanningDateHelpers.addDays(1, to: selectedDate)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)

                Button {
                    isDatePickerPresented = true
                } label: {
                    Image(systemName: "calendar")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var writable: Bool {
        guard let role = authStore.me?.role else { return false }
        return role == .direction || role == .coach
    }

    private var isReadOnlyRole: Bool {
        guard let role = authStore.me?.role else { return false }
        return role == .player || role == .parent
    }

    private var requiresSelection: Bool {
        guard let role = authStore.me?.role else { return false }
        return (role == .direction || role == .coach) && !teamScopeStore.teams.isEmpty
    }

    private var teamScopedWritable: Bool {
        writable && (!requiresSelection || teamScopeStore.selectedTeamID != nil)
    }

    private var selectedTeamName: String? {
        guard let selectedTeamID = teamScopeStore.selectedTeamID else { return nil }
        return teamScopeStore.teams.first(where: { $0.id == selectedTeamID })?.name
    }

    private var coachManagedTeamIDs: Set<String>? {
        guard authStore.me?.role == .coach else { return nil }
        return Set(authStore.me?.managedTeamIds ?? [])
    }

    private var visibleTrainings: [Training] {
        filterByScope(viewModel.trainings, teamID: \.teamId)
    }

    private var visibleMatchdays: [Matchday] {
        filterByScope(viewModel.matchdays, teamID: \.teamId)
    }

    private var dayTrainings: [Training] {
        visibleTrainings.filter { PlanningDateHelpers.storageKey(fromISO8601: $0.date) == selectedDayKey }
    }

    private var dayMatchdays: [Matchday] {
        visibleMatchdays.filter { PlanningDateHelpers.storageKey(fromISO8601: $0.date) == selectedDayKey }
    }

    private var selectedDayKey: String {
        PlanningDateHelpers.storageKey(for: selectedDate)
    }

    private var isTodaySelected: Bool {
        selectedDayKey == PlanningDateHelpers.storageKey(for: PlanningDateHelpers.today)
    }

    private var trainingDayKeys: Set<String> {
        Set(visibleTrainings.map { PlanningDateHelpers.storageKey(fromISO8601: $0.date) })
    }

    private var matchdayDayKeys: Set<String> {
        Set(visibleMatchdays.map { PlanningDateHelpers.storageKey(fromISO8601: $0.date) })
    }

    private var matchdayLocations: [String] {
        Array(Set(visibleMatchdays.compactMap { value in
            let trimmed = value.lieu?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }))
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func teamSubtitle(for teamID: String?) -> String? {
        guard authStore.me?.role == .direction else { return nil }
        guard let teamID else { return "Équipe: Non renseignée" }
        let teamName = teamScopeStore.teams.first(where: { $0.id == teamID })?.name ?? teamID
        return "Équipe: \(teamName)"
    }

    private func trainingSubtitle(for training: Training) -> String? {
        var lines: [String] = []
        if let trainingTime = trainingTimeSubtitle(from: training.date) {
            lines.append(trainingTime)
        }
        if let teamSubtitle = teamSubtitle(for: training.teamId) {
            lines.append(teamSubtitle)
        }
        if writable, let summary = training.intentSummary {
            lines.append("Intentions: \(summary.presentCount)/\(summary.totalPlayers) présents")
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private func trainingTimeSubtitle(from isoDate: String) -> String? {
        guard let date = DateFormatters.parseISODate(isoDate) else { return nil }
        return "Horaire: \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func setTrainingIntent(trainingID: String, present: Bool) async {
        if updatingTrainingIntentIDs.contains(trainingID) { return }
        updatingTrainingIntentIDs.insert(trainingID)
        defer { updatingTrainingIntentIDs.remove(trainingID) }
        do {
            try await IzifootAPI().setTrainingIntent(trainingID: trainingID, present: present)
            await viewModel.load()
        } catch {
            if !error.isCancellationError {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func filterByScope<Item>(_ items: [Item], teamID: KeyPath<Item, String?>) -> [Item] {
        let coachScoped: [Item]
        if let managed = coachManagedTeamIDs {
            coachScoped = items.filter { item in
                guard let currentTeamID = item[keyPath: teamID] else { return true }
                return managed.contains(currentTeamID)
            }
        } else {
            coachScoped = items
        }

        if requiresSelection && teamScopeStore.selectedTeamID == nil {
            return []
        }
        guard let selectedTeamID = teamScopeStore.selectedTeamID else {
            return coachScoped
        }
        return coachScoped.filter { item in
            guard let currentTeamID = item[keyPath: teamID] else { return true }
            return currentTeamID == selectedTeamID
        }
    }
}

private enum PlanningDateHelpers {
    static let calendar = Calendar(identifier: .gregorian)
    static let today = calendar.startOfDay(for: Date())

    static func defaultSelectedDate(storedValue: String?) -> Date {
        guard let storedValue, let parsed = parseStorageKey(storedValue) else { return today }
        return parsed
    }

    static func parseStorageKey(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func storageKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func storageKey(fromISO8601 value: String) -> String {
        guard let date = DateFormatters.parseISODate(value) else { return value }
        return storageKey(for: date)
    }

    static func addDays(_ amount: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: amount, to: date).map { calendar.startOfDay(for: $0) } ?? date
    }

    static func title(for date: Date) -> String {
        dateTitleFormatter.string(from: date).capitalized
    }

    static func monthLabel(for date: Date) -> String {
        monthFormatter.string(from: date).capitalized
    }

    static let dateTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM yyyy"
        return formatter
    }()

    static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}

private struct PlanningSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PlanningEventRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(uiColor: .tertiarySystemBackground), in: shape)
        .overlay {
            shape
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.05)
                        : Color.black.opacity(0.06),
                    lineWidth: 1
                )
        }
    }
}

private struct PlanningDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedDate: Date
    let trainingDayKeys: Set<String>
    let matchdayDayKeys: Set<String>

    @State private var pickerMonth = PlanningDateHelpers.today

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    Button {
                        pickerMonth = PlanningDateHelpers.calendar.date(byAdding: .month, value: -1, to: pickerMonth) ?? pickerMonth
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Text(PlanningDateHelpers.monthLabel(for: pickerMonth))
                        .font(.headline)

                    Spacer()

                    Button {
                        pickerMonth = PlanningDateHelpers.calendar.date(byAdding: .month, value: 1, to: pickerMonth) ?? pickerMonth
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                    ForEach(["L", "M", "M", "J", "V", "S", "D"], id: \.self) { label in
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(calendarCells.indices, id: \.self) { index in
                        if let date = calendarCells[index] {
                            let key = PlanningDateHelpers.storageKey(for: date)
                            let isSelected = key == PlanningDateHelpers.storageKey(for: selectedDate)

                            Button {
                                selectedDate = date
                                dismiss()
                            } label: {
                                VStack(spacing: 6) {
                                    Text("\(PlanningDateHelpers.calendar.component(.day, from: date))")
                                        .font(.subheadline.weight(.medium))
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(trainingDayKeys.contains(key) ? Color.accentColor : .clear)
                                            .frame(width: 6, height: 6)
                                        Circle()
                                            .fill(matchdayDayKeys.contains(key) ? Color.orange : .clear)
                                            .frame(width: 6, height: 6)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear
                                .frame(height: 42)
                        }
                    }
                }

                HStack(spacing: 16) {
                    Label("Entraînement", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Label("Plateau", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Choisir une date")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                let components = PlanningDateHelpers.calendar.dateComponents([.year, .month], from: selectedDate)
                pickerMonth = PlanningDateHelpers.calendar.date(from: components) ?? selectedDate
            }
        }
    }

    private var calendarCells: [Date?] {
        let monthStart = PlanningDateHelpers.calendar.date(
            from: PlanningDateHelpers.calendar.dateComponents([.year, .month], from: pickerMonth)
        ) ?? pickerMonth
        let startWeekday = (PlanningDateHelpers.calendar.component(.weekday, from: monthStart) + 5) % 7
        let dayRange = PlanningDateHelpers.calendar.range(of: .day, in: .month, for: monthStart) ?? 1 ..< 1

        return Array(repeating: nil, count: startWeekday) + dayRange.compactMap { day in
            PlanningDateHelpers.calendar.date(
                from: DateComponents(
                    year: PlanningDateHelpers.calendar.component(.year, from: monthStart),
                    month: PlanningDateHelpers.calendar.component(.month, from: monthStart),
                    day: day
                )
            )
        }
    }
}

private struct CreatePlateauSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selectedDate: Date
    @Binding var location: String
    let suggestedLocations: [String]
    let onSubmit: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    Text(PlanningDateHelpers.title(for: selectedDate))
                }

                Section("Lieu du plateau") {
                    TextField("Ex. Stade municipal", text: $location)
                }

                if !suggestedLocations.isEmpty {
                    Section("Lieux déjà utilisés") {
                        ForEach(suggestedLocations, id: \.self) { suggestion in
                            Button(suggestion) {
                                location = suggestion
                            }
                        }
                    }
                }
            }
            .navigationTitle("Créer un plateau")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continuer") {
                        Task {
                            await onSubmit()
                        }
                    }
                    .disabled(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
