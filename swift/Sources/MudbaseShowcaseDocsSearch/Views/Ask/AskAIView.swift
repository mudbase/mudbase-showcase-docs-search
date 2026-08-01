import SwiftUI

/// Mirrors `../web/src/app/ask/page.tsx` + `AskAIPanel.tsx`, with one deliberate, documented
/// difference: this screen never shows an LLM-synthesized answer — see `AskAIViewModel`'s doc
/// comment and this package's README "Ask AI architecture" for exactly why (short version: doing
/// so would require embedding a secret in the app bundle, which this project's security rules rule
/// out absolutely). What it shows instead is the real, on-device keyword retrieval ranking — using
/// the same weights the deployed Mudbase Function itself uses — presented honestly as ranked
/// source documents rather than a fabricated chat answer.
struct AskAIView: View {
    @StateObject private var viewModel: AskAIViewModel
    @EnvironmentObject private var sessionStore: SessionStore
    private let config: AppConfig

    init(config: AppConfig) {
        self.config = config
        _viewModel = StateObject(wrappedValue: AskAIViewModel(config: config))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                askCard
                architectureNotice

                if viewModel.noMatch {
                    Text("No documents in the library matched that question closely enough. Try rephrasing, or add a document that covers it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !viewModel.results.isEmpty {
                    resultsSection
                }

                Divider()

                RecentSearchesView(config: config)
            }
            .padding()
        }
        .navigationTitle("Ask AI")
        .docsSearchNavigationDestinations(config: config)
        .task { await viewModel.loadLibrary() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ask a question in plain language.")
                .font(.headline)
            Text("This app ranks the library's documents by keyword relevance — the same ranking the real, deployed retrieval Function produces — and shows you the closest matches with citations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var askCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage = viewModel.errorMessage {
                InlineBanner(message: errorMessage)
            }
            TextEditor(text: $viewModel.question)
                .frame(minHeight: 80)
                .overlay(alignment: .topLeading) {
                    if viewModel.question.isEmpty {
                        Text("e.g. How do I reset my password?")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            Button {
                Task { await viewModel.ask(currentUser: sessionStore.user) }
            } label: {
                if viewModel.isAsking {
                    ProgressView()
                } else if viewModel.isLoadingLibrary {
                    Text("Loading library…")
                } else {
                    Text("Ask AI")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canAsk)
        }
    }

    private var architectureNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("About this Ask AI", systemImage: "info.circle")
                .font(.caption.weight(.semibold))
            Text("Retrieval below runs live, on-device, against this project's real documents. This build doesn't include an AI-generated written answer: that step needs a server-side proxy to call an LLM provider, which this mobile app deliberately does not embed a secret for. See the README for the full reasoning.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top matching documents")
                .font(.subheadline.weight(.semibold))
            ForEach(viewModel.results) { result in
                NavigationLink(value: DocumentReference(documentId: result.documentId)) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(result.title)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("score \(result.score)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(result.snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
