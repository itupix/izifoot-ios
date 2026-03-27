import SwiftUI

@MainActor
final class TrainingDetailViewModel: ObservableObject {
    @Published private(set) var attendance: [AttendanceRow] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI = IzifootAPI()) {
        self.api = api
    }

    func load(trainingID: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            attendance = try await api.attendanceBySession(type: "TRAINING", sessionID: trainingID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TrainingDetailView: View {
    let training: Training

    @StateObject private var viewModel = TrainingDetailViewModel()

    var body: some View {
        List {
            Section("Informations") {
                LabeledContent("Date", value: DateFormatters.display(training.date))
                if let status = training.status {
                    LabeledContent("Statut", value: status)
                }
            }

            Section("Présences") {
                if viewModel.attendance.isEmpty {
                    Text("Aucune présence enregistrée")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(viewModel.attendance.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.playerId)
                        Spacer()
                        Image(systemName: row.present ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(row.present ? .green : .red)
                    }
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView("Chargement")
            }
        }
        .navigationTitle("Entraînement")
        .task {
            await viewModel.load(trainingID: training.id)
        }
        .refreshable {
            await viewModel.load(trainingID: training.id)
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
