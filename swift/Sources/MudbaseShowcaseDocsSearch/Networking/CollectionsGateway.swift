import Foundation
import MudbaseSDK

/// Generic CRUD over `DataAPI`, parameterized by collection ID — the Swift equivalent of
/// `../web/src/lib/mudbase.ts`'s `getDocuments`/`getDocument`/`createDocument`/`updateDocument`/
/// `deleteDocument`. Every project-scoped `DataAPI` call needs `projectId` + `collectionId`, so
/// this fixes both once per gateway instance instead of threading them through every call site.
/// Ported verbatim from the sibling `mudbase-showcase-ecommerce`/`mudbase-showcase-social` Swift
/// ports' `Networking/CollectionsGateway.swift`.
struct CollectionsGateway {
    let projectId: String
    let collectionId: String

    struct ListResult {
        let documents: [MudbaseDocument]
        let pagination: Pagination?
    }

    /// - Parameters:
    ///   - filter: A Mongo-style filter dictionary, JSON-encoded exactly like the web client's
    ///     `getDocuments` (`params.set("filter", JSON.stringify(query.filter))`).
    func list(filter: [String: JSONValue] = [:], sort: String = "-createdAt", page: Int? = nil, limit: Int? = nil) async throws(ErrorResponse) -> ListResult {
        let filterString: String?
        if filter.isEmpty {
            filterString = nil
        } else {
            filterString = Self.encodeFilter(filter)
        }
        let projectId = self.projectId
        let collectionId = self.collectionId
        // Routed through `AccessTokenCoordinator` so an access token that expired mid-session
        // (real or anonymous — see that type's doc comment) transparently refreshes and retries
        // once instead of surfacing a raw 401.
        let response = try await AccessTokenCoordinator.shared.perform { () async throws(ErrorResponse) in
            try await DataAPI.listData(
                projectId: projectId,
                collectionId: collectionId,
                page: page,
                limit: limit,
                sort: sort,
                filter: filterString
            )
        }
        let documents = (response.data ?? []).compactMap(MudbaseDocument.init(listItem:))
        return ListResult(documents: documents, pagination: response.pagination)
    }

    func get(documentId: String) async throws(ErrorResponse) -> MudbaseDocument {
        let projectId = self.projectId
        let collectionId = self.collectionId
        let response = try await AccessTokenCoordinator.shared.perform { () async throws(ErrorResponse) in
            try await DataAPI.getData(projectId: projectId, collectionId: collectionId, documentId: documentId)
        }
        guard let data = response.data, let document = MudbaseDocument(rawDocument: data) else {
            throw ErrorResponse.error(-2, nil, nil, MudbaseClientError.malformedDocument)
        }
        return document
    }

    @discardableResult
    func create(fields: [String: JSONValue?]) async throws(ErrorResponse) -> MudbaseDocument {
        let projectId = self.projectId
        let collectionId = self.collectionId
        let body = JSONValue.object(fields)
        let response = try await AccessTokenCoordinator.shared.perform { () async throws(ErrorResponse) in
            try await DataAPI.createData(projectId: projectId, collectionId: collectionId, body: body)
        }
        guard let data = response.data, let document = MudbaseDocument(rawDocument: data) else {
            throw ErrorResponse.error(-2, nil, nil, MudbaseClientError.malformedDocument)
        }
        return document
    }

    @discardableResult
    func update(documentId: String, fields: [String: JSONValue?]) async throws(ErrorResponse) -> MudbaseDocument {
        let projectId = self.projectId
        let collectionId = self.collectionId
        let body = JSONValue.object(fields)
        let response = try await AccessTokenCoordinator.shared.perform { () async throws(ErrorResponse) in
            try await DataAPI.updateData(projectId: projectId, collectionId: collectionId, documentId: documentId, body: body)
        }
        guard let data = response.data, let document = MudbaseDocument(rawDocument: data) else {
            throw ErrorResponse.error(-2, nil, nil, MudbaseClientError.malformedDocument)
        }
        return document
    }

    func delete(documentId: String) async throws(ErrorResponse) {
        let projectId = self.projectId
        let collectionId = self.collectionId
        _ = try await AccessTokenCoordinator.shared.perform { () async throws(ErrorResponse) in
            try await DataAPI.deleteData(projectId: projectId, collectionId: collectionId, documentId: documentId)
        }
    }

    /// Encodes a `[String: JSONValue]` filter to the same compact JSON string
    /// `JSON.stringify(query.filter)` would produce on the web side.
    private static func encodeFilter(_ filter: [String: JSONValue]) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(JSONValue.dictionary(filter)) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
