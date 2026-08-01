import Foundation

/// Backs `LibraryView` — the document list + client-side search box. Mirrors
/// `../web/src/app/page.tsx`: fetches up to 100 documents sorted newest-first, then filters them
/// in-memory as the user types via `Retrieval.matchesSearchTerm` (no server round trip per
/// keystroke, same as the web page's `useMemo`).
@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var documents: [DocumentRecord] = []
    @Published var searchTerm = ""
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    private let documentsService: DocumentsService

    init(config: AppConfig) {
        documentsService = DocumentsService(config: config)
    }

    var filteredDocuments: [DocumentRecord] {
        documents.filter { Retrieval.matchesSearchTerm($0, term: searchTerm) }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            documents = try await documentsService.list()
        } catch {
            errorMessage = MudbaseAPIError.map(error).message
        }
    }

    /// Called after a document is deleted or created elsewhere so the list stays in sync without
    /// a full reload — mirrors the web app's own TanStack Query cache invalidation.
    func remove(documentId: String) {
        documents.removeAll { $0.id == documentId }
    }
}
