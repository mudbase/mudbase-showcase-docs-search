import SwiftUI

/// Mirrors `../web/src/app/documents/[id]/page.tsx`: full content, author, tags, and Edit/Delete
/// buttons gated to `user.id === document.authorId` (`isOwner` below) — the same client-side check
/// the web page performs; the real security boundary is this project's own collection permissions
/// (verified live), not this check.
struct DocumentDetailView: View {
    @StateObject private var viewModel: DocumentDetailViewModel
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    private let config: AppConfig
    @State private var isPresentingEdit = false
    @State private var isPresentingDeleteConfirm = false

    init(config: AppConfig, documentId: String) {
        self.config = config
        _viewModel = StateObject(wrappedValue: DocumentDetailViewModel(config: config, documentId: documentId))
    }

    var body: some View {
        content
            .navigationTitle(viewModel.document?.title ?? "Document")
            .inlineNavigationTitle()
            .toolbar {
                if viewModel.isOwner(currentUser: sessionStore.user) {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            isPresentingEdit = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            isPresentingDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete this document? This cannot be undone.",
                isPresented: $isPresentingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.delete() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $isPresentingEdit, onDismiss: { Task { await viewModel.load() } }) {
                if let document = viewModel.document, let user = sessionStore.user {
                    NavigationStack {
                        DocumentFormView(config: config, author: user, existingDocument: document)
                    }
                }
            }
            .onChange(of: viewModel.didDelete) { _, didDelete in
                if didDelete { dismiss() }
            }
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            LoadingView()
        } else if let errorMessage = viewModel.errorMessage, viewModel.document == nil {
            InlineErrorView(message: errorMessage) { Task { await viewModel.load() } }
        } else if let document = viewModel.document {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage = viewModel.errorMessage {
                        InlineBanner(message: errorMessage)
                    }

                    let tags = Formatting.parseTags(document.tags)
                    if !tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                    }

                    Text("\(document.authorName) · \(Formatting.dateTime(from: document.createdAt))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Divider()

                    Text(document.content)
                        .font(.body)
                        .textSelection(.enabled)

                    if viewModel.isDeleting {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                .padding()
            }
        } else {
            EmptyStateView(message: "This document isn't available.")
        }
    }
}
