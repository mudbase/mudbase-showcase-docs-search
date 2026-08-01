import Foundation
import MudbaseSDK

/// A normalized view over the two shapes `DataAPI` hands back: `DataListResponseDataInner` (list
/// results — `_id`/`createdAt`/`updatedAt` already typed, everything else in `additionalProperties`)
/// and a single document's raw `JSONValue` (from `DataResponse.data` on create/get/update). Domain
/// models (`DocumentRecord`, `SearchLogRecord`) build themselves from this rather than each
/// hand-rolling their own `DataListResponseDataInner`-vs-`JSONValue` branching. Ported verbatim from
/// the sibling `mudbase-showcase-ecommerce`/`mudbase-showcase-social` Swift ports'
/// `Models/MudbaseDocument.swift`.
struct MudbaseDocument {
    let id: String
    let createdAt: Date?
    let updatedAt: Date?
    let fields: [String: JSONValue]

    init(id: String, createdAt: Date?, updatedAt: Date?, fields: [String: JSONValue]) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fields = fields
    }

    init?(listItem: DataListResponseDataInner) {
        guard let id = listItem.id else { return nil }
        self.init(id: id, createdAt: listItem.createdAt, updatedAt: listItem.updatedAt, fields: listItem.additionalProperties)
    }

    /// `DataResponse.data` and `GetLocalSession200Response.user` are both untyped `JSONValue` —
    /// this reconstructs the same `{id, createdAt, updatedAt, ...fields}` shape from the raw
    /// dictionary, pulling out `_id`/`createdAt`/`updatedAt` the same way the generated
    /// `DataListResponseDataInner.init(from:)` does.
    init?(rawDocument value: JSONValue) {
        guard let dict = value.dictionaryValue, let id = dict["_id"]?.stringValue else { return nil }
        var fields = dict
        fields.removeValue(forKey: "_id")
        let createdAt = fields.removeValue(forKey: "createdAt").flatMap(MudbaseDocument.parseDate)
        let updatedAt = fields.removeValue(forKey: "updatedAt").flatMap(MudbaseDocument.parseDate)
        self.init(id: id, createdAt: createdAt, updatedAt: updatedAt, fields: fields)
    }

    private static func parseDate(_ value: JSONValue) -> Date? {
        guard let string = value.stringValue else { return nil }
        return ISO8601DateFormatter.mudbase.date(from: string)
    }

    subscript(_ key: String) -> JSONValue? { fields[key] }

    func string(_ key: String) -> String? { fields[key]?.stringValue }
    func int(_ key: String) -> Int? {
        if let intValue = fields[key]?.intValue { return intValue }
        if let doubleValue = fields[key]?.doubleValue { return Int(doubleValue) }
        return nil
    }
}

extension ISO8601DateFormatter {
    /// Mudbase timestamps include fractional seconds (e.g. `2026-08-01T10:00:00.000Z`) — the
    /// default `ISO8601DateFormatter()` rejects those without this option.
    static let mudbase: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
