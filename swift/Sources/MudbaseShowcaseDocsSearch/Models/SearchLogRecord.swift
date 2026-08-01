import Foundation

/// Mirrors `../web/src/types/document.ts`'s `SearchLogRecord` interface: `queryText`, optional
/// `userId`/`userName` (only ever a real signed-in user's ObjectId, never a placeholder string —
/// see `SearchLogService.log`), and `resultCount`.
struct SearchLogRecord: Identifiable, Equatable, Sendable {
    let id: String
    let queryText: String
    let userId: String?
    let userName: String?
    let resultCount: Int
    let createdAt: Date?

    init(document: MudbaseDocument) {
        id = document.id
        queryText = document.string("queryText") ?? ""
        userId = document.string("userId")
        userName = document.string("userName")
        resultCount = document.int("resultCount") ?? 0
        createdAt = document.createdAt
    }
}
