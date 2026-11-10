import SwiftUI

struct AttendancePlayerSplitView: View {
    let report: AttendanceReport
    @Binding var selectedPlayerID: String
    @Binding var query: String
    @State private var availableWidth: CGFloat = 0

    private var sidebarWidth: CGFloat { availableWidth >= 600 ? 220 : 132 }
    private var detailWidth: CGFloat { max(240, availableWidth - sidebarWidth - 24) }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 24) {
                sidebar.frame(width: sidebarWidth)
                detail.frame(width: detailWidth, alignment: .leading)
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: AttendanceSplitWidth.self, value: geometry.size.width)
            }
        }
        .onPreferenceChange(AttendanceSplitWidth.self) { availableWidth = $0 }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Rechercher un joueur", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Rechercher un joueur")
            let players = report.matrixPlayers.filter { query.isEmpty || $0.displayName.localizedStandardContains(query) }
            if players.isEmpty { Text("Aucun joueur trouvé.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(players) { player in
                Button {
                    selectedPlayerID = player.id
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Text(player.displayName).font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if selectedPlayerID == player.id { Image(systemName: "checkmark.circle.fill") }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(selectedPlayerID == player.id ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedPlayerID == player.id ? Color.accentColor : Color.primary)
                .accessibilityAddTraits(selectedPlayerID == player.id ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let player = report.players.first(where: { $0.id == selectedPlayerID }) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(player.displayName).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("Saison").font(.subheadline).foregroundStyle(.secondary)
                    Text(player.summary.percentage).font(.title.bold())
                }
                ForEach(player.months) { month in
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(AttendanceReport.monthLabel(month.month)).font(.headline).accessibilityAddTraits(.isHeader)
                            Text(month.summary.percentage).font(.title3.bold())
                        }
                        ForEach(report.matrixTrainings(in: month.month)) { training in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(AttendanceReport.trainingDateLabel(training.date)).font(.subheadline.weight(.medium))
                                if let status = player.status(for: training.id) {
                                    Label(status.label, systemImage: status.symbol).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        } else {
            Text("Choisissez un joueur pour consulter le détail de ses présences.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        }
    }
}

private struct AttendanceSplitWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
