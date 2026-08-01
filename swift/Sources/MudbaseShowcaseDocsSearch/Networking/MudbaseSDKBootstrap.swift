import Foundation
import MudbaseSDK

/// One-time configuration of the shared `MudbaseSDKAPIConfiguration` singleton every generated API
/// call reads by default (`apiConfiguration: MudbaseSDKAPIConfiguration = .shared`). Every
/// `RequestBuilder` merges `apiConfiguration.customHeaders` into its request at init time, so
/// setting the bearer token here once is enough for every subsequent SDK call in the process to
/// carry it automatically. Ported verbatim from the sibling `mudbase-showcase-ecommerce`/
/// `mudbase-showcase-social` Swift ports' `Networking/MudbaseSDKBootstrap.swift`.
enum MudbaseSDKBootstrap {
    private static let authorizationHeaderName = "Authorization"

    static func configure(baseURL: URL) {
        MudbaseSDKAPIConfiguration.shared.basePath = baseURL.absoluteString
    }

    static func setAccessToken(_ token: String) {
        MudbaseSDKAPIConfiguration.shared.customHeaders[authorizationHeaderName] = "Bearer \(token)"
    }

    static func clearAccessToken() {
        MudbaseSDKAPIConfiguration.shared.customHeaders.removeValue(forKey: authorizationHeaderName)
    }
}

extension JSONValue {
    /// Builds a `.dictionary` `JSONValue`, dropping any key whose value is `nil` — the equivalent
    /// of `JSON.stringify`'s own `undefined`-key-omission behavior, needed so partial `PATCH`
    /// bodies (`updateData`) don't overwrite untouched fields with explicit nulls.
    static func object(_ fields: [String: JSONValue?]) -> JSONValue {
        var result: [String: JSONValue] = [:]
        for (key, value) in fields {
            if let value { result[key] = value }
        }
        return .dictionary(result)
    }
}
