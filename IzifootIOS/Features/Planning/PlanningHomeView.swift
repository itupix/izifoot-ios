import SwiftUI

@MainActor
final class PlanningHomeViewModel: ObservableObject {
    @Published private(set) var trainings: [Training] = []
    @Published private(set) var matchdays: [Matchday] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI = IzifootAPI()) {
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let trainingsTask = api.trainings()
            async let matchdaysTask = api.matchdays()
            trainings = try await trainingsTask.sorted { $0.date > $1.date }
            matchdays = try await matchdaysTask.sorted { $0.date > $1.date }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTraining(date: Date) async {
        do {
            let newTraining = try await api.createTraining(dateISO8601: DateFormatters.isoString(from: date))
            trainings.insert(newTraining, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createMatchday(date: Date, location: String, startTime: String?, meetingTime: String?) async {
        do {
            let newMatchday = try await api.createMatchday(
                dateISO8601: DateFormatters.isoString(from: date),
                lieu: location,
                startTime: startTime,
                meetingTime: meetingTime
            )
            matchdays.insert(newMatchday, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PlanningHomeView: View {
    @StateObject private var viewModel = PlanningHomeViewModel()
    @State private var createItemSheet: CreatePlanningItemSheet.Kind?

    var body: some View {
        NavigationStack {
            List {
                Section("Entraînements") {
                    if viewModel.trainings.isEmpty {
                        Text("Aucun entraînement")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.trainings) { training in
                        NavigationLink {
                            TrainingDetailView(training: training)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(DateFormatters.display(training.date))
                                if let status = training.status {
                                    Text(status)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Plateaux") {
                    if viewModel.matchdays.isEmpty {
                        Text("Aucun plateau")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.matchdays) { matchday in
                        NavigationLink {
                            MatchdayDetailView(matchday: matchday)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(DateFormatters.display(matchday.date))
                                Text(matchday.lieu ?? "Lieu non renseigné")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Chargement")
                }
            }
            .navigationTitle("Planning")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TeamScopePicker()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Créer un entraînement") {
                            createItemSheet = .training
                        }
                        Button("Créer un plateau") {
                            createItemSheet = .matchday
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await viewModel.load()
            }
            .task {
                await viewModel.load()
            }
            .sheet(item: $createItemSheet) { kind in
                CreatePlanningItemSheet(kind: kind) { payload in
                    switch payload {
                    case let .training(date):
                        await viewModel.createTraining(date: date)
                    case let .matchday(date, location, startTime, meetingTime):
                        await viewModel.createMatchday(date: date, location: location, startTime: startTime, meetingTime: meetingTime)
                    }
                    createItemSheet = nil
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
}

struct CreatePlanningItemSheet: View {
    enum Kind: String, Identifiable {
        case training
        case matchday

        var id: String { rawValue }
    }

    enum Payload {
        case training(Date)
        case matchday(Date, String, String?, String?)
    }

    @Environment(\.dismiss) private var dismiss

    let kind: Kind
    let onSubmit: (Payload) async -> Void

    @State private var date = Date()
    @State private var location = ""
    @State private var startTime = ""
    @State private var meetingTime = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date)

                if kind == .matchday {
                    TextField("Lieu", text: $location)
                    TextField("Heure de début (HH:mm)", text: $startTime)
                    TextField("Heure de rendez-vous (HH:mm)", text: $meetingTime)
                }
            }
            .navigationTitle(kind == .training ? "Nouvel entraînement" : "Nouveau plateau")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        Task {
                            switch kind {
                            case .training:
                                await onSubmit(.training(date))
                            case .matchday:
                                await onSubmit(.matchday(
                                    date,
                                    location,
                                    startTime.isEmpty ? nil : startTime,
                                    meetingTime.isEmpty ? nil : meetingTime
                                ))
                            }
                        }
                    }
                    .disabled(kind == .matchday && location.isEmpty)
                }
            }
        }
    }
}
