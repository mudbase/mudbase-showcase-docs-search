import Foundation
import MudbaseSDK

/// Reads and writes against the `documents` collection. Mirrors `../web/src/hooks/useCollection.ts`'s
/// `useDocuments`/`useDocument`/`useCreateDocument`/`useUpdateDocument`/`useDeleteDocument`, as used
/// by the library, document detail, and document form screens.
struct DocumentsService {
    private let gateway: CollectionsGateway

    init(config: AppConfig) {
        gateway = CollectionsGateway(projectId: config.projectId, collectionId: config.documentsCollectionId)
    }

    /// Mirrors the library page's own fetch (`page.tsx`: `useDocuments(..., { sort: "-createdAt",
    /// limit: 100 })`) — the client-side search box and Ask AI's retrieval both operate over this
    /// same fetched batch, matching the reference web app's own bounded, non-paginated library.
    func list(limit: Int = 100) async throws(ErrorResponse) -> [DocumentRecord] {
        let result = try await gateway.list(sort: "-createdAt", limit: limit)
        return result.documents.map(DocumentRecord.init(document:))
    }

    /// Ask AI fetches a larger batch than the library screen (mirrors `AskAIPanel.tsx`'s own
    /// `useDocuments(..., { limit: 200 })`) since a wider candidate pool improves retrieval quality
    /// without needing pagination UI.
    func listForRetrieval(limit: Int = 200) async throws(ErrorResponse) -> [DocumentRecord] {
        let result = try await gateway.list(sort: "-createdAt", limit: limit)
        return result.documents.map(DocumentRecord.init(document:))
    }

    func get(id: String) async throws(ErrorResponse) -> DocumentRecord {
        DocumentRecord(document: try await gateway.get(documentId: id))
    }

    @discardableResult
    func create(title: String, content: String, tags: String, authorId: String, authorName: String) async throws(ErrorResponse) -> DocumentRecord {
        let fields: [String: JSONValue?] = [
            "title": .string(title),
            "content": .string(content),
            "tags": .string(tags),
            "authorId": .string(authorId),
            "authorName": .string(authorName),
        ]
        return DocumentRecord(document: try await gateway.create(fields: fields))
    }

    @discardableResult
    func update(id: String, title: String, content: String, tags: String) async throws(ErrorResponse) -> DocumentRecord {
        let fields: [String: JSONValue?] = [
            "title": .string(title),
            "content": .string(content),
            "tags": .string(tags),
        ]
        return DocumentRecord(document: try await gateway.update(documentId: id, fields: fields))
    }

    func delete(id: String) async throws(ErrorResponse) {
        try await gateway.delete(documentId: id)
    }
}
