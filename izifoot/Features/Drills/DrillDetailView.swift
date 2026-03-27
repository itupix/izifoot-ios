import Combine
import SwiftUI

@MainActor
final class DrillDetailViewModel: ObservableObject {
    @Published private(set) var drill: Drill?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api: IzifootAPI

    init(api: IzifootAPI = IzifootAPI()) {
        self.api = api
    }

    func load(id: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            drill = try await api.drill(id: id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DrillDetailView: View {
    let drillID: String

    @StateObject private var viewModel = DrillDetailViewModel()

    var body: some View {
        List {
            if let drill = viewModel.drill {
                Section("Détails") {
                    LabeledContent("Catégorie", value: drill.category)
                }

                Section("Description") {
                    Text(drill.description)
                }

                if !drill.tags.isEmpty {
                    Section("Tags") {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(drill.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.thinMaterial, in: Capsule())
                                }
                            }
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
        .navigationTitle(viewModel.drill?.title ?? "Exercice")
        .task {
            await viewModel.load(id: drillID)
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
