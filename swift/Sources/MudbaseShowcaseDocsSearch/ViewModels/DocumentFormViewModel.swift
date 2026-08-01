import Foundation

/// Mirrors `../web/src/components/documents/DocumentForm.tsx`'s zod schema — re-implemented as
/// plain validation since this project has no zod dependency. Handles both "New document"
/// (`existingDocument == nil`) and "Edit document" (`existingDocument` switches the save path from
/// `create` to `update`), exactly like `documents/new/page.tsx` vs. `documents/[id]/edit/page.tsx`.
@MainActor
final class DocumentFormViewModel: ObservableObject {
    private static let maxTitleLength = 200
    private static let maxContentLength = 50_000
    private static let maxTagsLength = 500

    @Published var title: String
    @Published var content: String
    @Published var tags: String
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    @Published private(set) var savedDocument: DocumentRecord?

    private let service: DocumentsService
    private let author: AppUser
    private let existingDocumentId: String?

    init(config: AppConfig, author: AppUser, existingDocument: DocumentRecord? = nil) {
        service = DocumentsService(config: config)
        self.author = author
        existingDocumentId = existingDocument?.id
        title = existingDocument?.title ?? ""
        content = existingDocument?.content ?? ""
        tags = existingDocument?.tags ?? ""
    }

    var isEditing: Bool { existingDocumentId != nil }

    private var validationError: String? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty { return "Title is required" }
        if title.count > Self.maxTitleLength { return "Title is too long" }
        if trimmedContent.isEmpty { return "Content is required" }
        if content.count > Self.maxContentLength { return "Content is too long" }
        if tags.count > Self.maxTagsLength { return "Tags are too long" }
        return nil
    }

    func save() async {
        if let validationError {
            errorMessage = validationError
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            if let existingDocumentId {
                savedDocument = try await service.update(id: existingDocumentId, title: title, content: content, tags: tags)
            } else {
                savedDocument = try await service.create(
                    title: title,
                    content: content,
                    tags: tags,
                    authorId: author.id,
                    authorName: author.displayName
                )
            }
        } catch {
            errorMessage = MudbaseAPIError.map(error).message
        }
    }
}
