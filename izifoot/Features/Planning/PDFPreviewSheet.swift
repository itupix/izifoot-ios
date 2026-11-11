import PDFKit
import SwiftUI
import UIKit

struct PDFPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isSharing = false

    let url: URL
    let document: PDFDocument?
    var title = "Résumé de la séance"

    var body: some View {
        NavigationStack {
            Group {
                if let document, document.pageCount > 0 {
                    TrainingSummaryPDFView(document: document)
                } else {
                    Text("Impossible d’afficher le PDF.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isSharing = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Partager le PDF")
                    .disabled(document == nil || document?.pageCount == 0)
                }
            }
            .sheet(isPresented: $isSharing) {
                TrainingSummaryShareSheet(url: url)
            }
        }
    }
}

private struct TrainingSummaryPDFView: UIViewControllerRepresentable {
    let document: PDFDocument

    func makeUIViewController(context: Context) -> TrainingSummaryPDFViewController {
        TrainingSummaryPDFViewController(document: document)
    }

    func updateUIViewController(_ controller: TrainingSummaryPDFViewController, context: Context) {}
}

private final class TrainingSummaryPDFViewController: UIViewController {
    private let document: PDFDocument
    private var pdfView: PDFView?
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    init(document: PDFDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.accessibilityLabel = "Chargement du PDF"
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        loadingIndicator.startAnimating()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // PDFKit's initial layout runs only after the native sheet transition has completed.
        // Keep the same view when returning from sharing, preserving scroll position and zoom.
        guard pdfView == nil, !isBeingDismissed else { return }
        let pdf = PDFView()
        pdf.translatesAutoresizingMaskIntoConstraints = false
        pdf.autoScales = true
        pdf.displayMode = .singlePageContinuous
        pdf.displayDirection = .vertical
        view.addSubview(pdf)
        NSLayoutConstraint.activate([
            pdf.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdf.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdf.topAnchor.constraint(equalTo: view.topAnchor),
            pdf.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pdf.document = document
        pdfView = pdf
        loadingIndicator.stopAnimating()
        loadingIndicator.removeFromSuperview()
    }
}

private struct TrainingSummaryShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
