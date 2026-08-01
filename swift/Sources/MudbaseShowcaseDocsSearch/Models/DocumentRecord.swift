import Foundation

/// Mirrors `../web/src/types/document.ts`'s `DocumentRecord` interface exactly: `title`, `content`,
/// optional comma-separated `tags`, and denormalized `authorId`/`authorName` (this project has no
/// `users` collection — see README "Known limitations").
struct DocumentRecord: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let content: String
    /// Comma-separated tags, e.g. "billing,invoices". Optional field on the collection schema —
    /// parse with `Formatting.parseTags(_:)` before display.
    let tags: String?
    let authorId: String
    let authorName: String
    let createdAt: Date?
    let updatedAt: Date?

    init(id: String, title: String, content: String, tags: String?, authorId: String, authorName: String, createdAt: Date?, updatedAt: Date?) {
        self.id = id
        self.title = title
        self.content = content
        self.tags = tags
        self.authorId = authorId
        self.authorName = authorName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(document: MudbaseDocument) {
        id = document.id
        title = document.string("title") ?? ""
        content = document.string("content") ?? ""
        tags = document.string("tags")
        authorId = document.string("authorId") ?? ""
        authorName = document.string("authorName") ?? ""
        createdAt = document.createdAt
        updatedAt = document.updatedAt
    }
}
