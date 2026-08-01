import Foundation
import MudbaseSDK

/// Reads and writes against the `search_log` collection. Mirrors `../web/src/components/ask/
/// AskAIPanel.tsx`'s `useCreateDocument<SearchLogRecord>` write and
/// `../web/src/components/ask/RecentSearches.tsx`'s `useDocuments<SearchLogRecord>` read.
struct SearchLogService {
    private let gateway: CollectionsGateway

    init(config: AppConfig) {
        gateway = CollectionsGateway(projectId: config.projectId, collectionId: config.searchLogCollectionId)
    }

    /// `userId` must be a real signed-in user's ObjectId or omitted entirely — never a placeholder
    /// string (this project's own `*Id`-suffixed filter fields must be real 24-char hex ObjectIds;
    /// a log write is not itself filtered by `userId`, but the field is still typed as "real
    /// ObjectId or absent" on the collection schema, matching the web app's own
    /// `...(user?.id ? { userId: user.id } : {})` spread).
    @discardableResult
    func log(queryText: String, resultCount: Int, userId: String?, userName: String?) async throws(ErrorResponse) -> SearchLogRecord {
        let fields: [String: JSONValue?] = [
            "queryText": .string(queryText),
            "resultCount": .int(resultCount),
            "userId": userId.map(JSONValue.string),
            "userName": userName.map(JSONValue.string),
        ]
        return SearchLogRecord(document: try await gateway.create(fields: fields))
    }

    /// Mirrors `RecentSearches.tsx`'s `useDocuments(..., { sort: "-createdAt", limit: 10 })`.
    func recent(limit: Int = 10) async throws(ErrorResponse) -> [SearchLogRecord] {
        let result = try await gateway.list(sort: "-createdAt", limit: limit)
        return result.documents.map(SearchLogRecord.init(document:))
    }
}
