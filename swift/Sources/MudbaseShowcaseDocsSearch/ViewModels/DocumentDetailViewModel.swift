import Foundation

/// Backs `DocumentDetailView`. Mirrors `../web/src/app/documents/[id]/page.tsx`: loads the full
/// document, and exposes ownership-scoped delete (`isOwner` gates the Edit/Delete UI in the view —
/// the same client-side check the web page performs; the real security boundary is this project's
/// own collection permissions, verified live, not this check).
@MainActor
final class DocumentDetailViewModel: ObservableObject {
    @Published private(set) var document: DocumentRecord?
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var isDeleting = false
    @Published private(set) var didDelete = false

    let documentId: String
    private let documentsService: DocumentsService

    init(config: AppConfig, documentId: String) {
        self.documentId = documentId
        documentsService = DocumentsService(config: config)
    }

    func isOwner(currentUser: AppUser?) -> Bool {
        guard let currentUser, let document else { return false }
        return currentUser.id == document.authorId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            document = try await documentsService.get(id: documentId)
        } catch {
            errorMessage = MudbaseAPIError.map(error).message
        }
    }

    func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await documentsService.delete(id: documentId)
            didDelete = true
        } catch {
            errorMessage = MudbaseAPIError.map(error).message
        }
    }
}
