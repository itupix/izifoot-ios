import SwiftUI

/// The fixed names column and date columns share row metrics inside one vertical list row.
struct AttendanceMonthTable: View {
    let report: AttendanceReport
    let month: String
    @ScaledMetric(relativeTo: .body) private var rowHeight = 68
    @ScaledMetric(relativeTo: .caption) private var headerHeight = 62
    @ScaledMetric(relativeTo: .caption) private var dateWidth = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 0) {
                namesColumn
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(report.matrixTrainings(in: month)) { training in
                            dateColumn(training)
                        }
                    }
                }
            }
            .frame(height: headerHeight + CGFloat(report.matrixPlayers.count) * rowHeight)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            legend
        }
        .padding(.vertical, 4)
    }

    private var namesColumn: some View {
        VStack(spacing: 0) {
            Text("Joueur\nTaux du mois")
                .lineLimit(3)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: headerHeight, maxHeight: headerHeight, alignment: .leading)
                .padding(.horizontal, 8)
                .accessibilityAddTraits(.isHeader)
            ForEach(report.matrixPlayers) { player in
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.displayName).font(.subheadline.weight(.medium)).lineLimit(2)
                    Text(player.months.first { $0.month == month }?.summary.percentage ?? "—")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
                .padding(.horizontal, 8)
                .overlay(alignment: .top) { Divider() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(player.displayName), taux du mois : \(player.months.first { $0.month == month }?.summary.percentage ?? "—")")
            }
        }
        .frame(width: 132)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func dateColumn(_ training: AttendanceReport.Training) -> some View {
        VStack(spacing: 0) {
            Text(AttendanceReport.trainingDateLabel(training.date, compact: true))
                .font(.caption.monospacedDigit().weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(width: dateWidth, height: headerHeight)
                .accessibilityLabel(AttendanceReport.trainingDateLabel(training.date, style: .full))
                .accessibilityAddTraits(.isHeader)
            ForEach(report.matrixPlayers) { player in
                indicator(player.status(for: training.id))
                    .frame(width: dateWidth, height: rowHeight)
                    .overlay(alignment: .top) { Divider() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(player.displayName), \(AttendanceReport.trainingDateLabel(training.date, style: .full)), \(player.status(for: training.id)?.label ?? "Statut indisponible")")
            }
        }
    }

    @ViewBuilder private func indicator(_ status: AttendanceReport.Status?) -> some View {
        switch status {
        case .present:
            Circle().fill(Color.green).frame(width: 14, height: 14)
        case .absent:
            Circle().fill(Color.red).frame(width: 14, height: 14)
        case .notApplicable:
            Circle().fill(Color.gray).frame(width: 14, height: 14)
        case .unrecorded:
            Circle().stroke(Color.secondary, lineWidth: 1.5).frame(width: 14, height: 14)
        case .upcoming:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .cancelled:
            Image(systemName: "minus").foregroundStyle(.secondary)
        case nil:
            Image(systemName: "questionmark").foregroundStyle(.secondary)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Légende").font(.caption.weight(.semibold))
            ForEach([AttendanceReport.Status.present, .absent, .notApplicable, .unrecorded, .upcoming, .cancelled], id: \.rawValue) { status in
                HStack(spacing: 8) {
                    indicator(status).frame(width: 20, height: 20).accessibilityHidden(true)
                    Text(status.label).font(.caption)
                }
            }
        }
    }

}
