import SwiftUI

/// Mirrors `../web/src/app/page.tsx` — the document library: search box + list, with a "New
/// document" toolbar action gated to a real signed-in user (guests are routed to the Account tab's
/// sign-in screen via `TabRouter`, the native equivalent of the web app's `router.push("/login")`).
struct LibraryView: View {
    @StateObject private var viewModel: LibraryViewModel
    private let config: AppConfig
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var tabRouter: TabRouter
    @State private var isPresentingNewDocument = false

    init(config: AppConfig) {
        self.config = config
        _viewModel = StateObject(wrappedValue: LibraryViewModel(config: config))
    }

    var body: some View {
        content
            .navigationTitle("Document library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if sessionStore.isSignedIn {
                            isPresentingNewDocument = true
                        } else {
                            tabRouter.routeToSignIn()
                        }
                    } label: {
                        Label("New document", systemImage: "plus")
                    }
                }
            }
            .docsSearchNavigationDestinations(config: config)
            .sheet(isPresented: $isPresentingNewDocument, onDismiss: { Task { await viewModel.load() } }) {
                if let user = sessionStore.user {
                    NavigationStack {
                        DocumentFormView(config: config, author: user, existingDocument: nil)
                    }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 12) {
            SearchBarView(text: $viewModel.searchTerm)
                .padding(.horizontal)
                .padding(.top, 8)

            if viewModel.isLoading {
                LoadingView()
            } else if let errorMessage = viewModel.errorMessage {
                InlineErrorView(message: errorMessage) { Task { await viewModel.load() } }
            } else if viewModel.filteredDocuments.isEmpty {
                EmptyStateView(
                    message: viewModel.searchTerm.isEmpty
                        ? "No documents in the library yet."
                        : "No documents match \"\(viewModel.searchTerm)\"."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.filteredDocuments) { document in
                            NavigationLink(value: DocumentReference(documentId: document.id)) {
                                DocumentCardView(document: document)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
    }
}
