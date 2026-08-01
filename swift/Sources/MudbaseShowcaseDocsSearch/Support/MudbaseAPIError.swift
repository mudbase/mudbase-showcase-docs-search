import Foundation
import MudbaseSDK

/// The generated SDK surfaces every failed request as `ErrorResponse.error(Int, Data?, URLResponse?, Error)`
/// with no built-in message extraction. The platform's own error bodies are consistently shaped
/// like `{ "error": "..." }` or `{ "message": "..." }` (see `../web/src/lib/mudbase.ts`'s hand-rolled
/// client for the same convention) — this decodes that shape when present and otherwise falls back
/// to a status-code-derived message so no failure ever surfaces a raw `Error` description to a
/// user. Ported verbatim from the sibling `mudbase-showcase-ecommerce`/`mudbase-showcase-social`
/// Swift ports' `Support/MudbaseAPIError.swift`.
enum MudbaseAPIError {
    private struct ErrorBody: Decodable {
        let error: String?
        let message: String?
        let code: String?
        let reason: String?
    }

    struct DisplayableError: Error, Equatable {
        let statusCode: Int
        let message: String
        /// e.g. "EMAIL_VERIFICATION_REQUIRED" — callers switch on this when the UI needs to branch
        /// on a specific server-side reason rather than just show text.
        let code: String?
    }

    static func map(_ error: Error) -> DisplayableError {
        guard case let ErrorResponse.error(statusCode, data, _, underlying) = error else {
            return DisplayableError(statusCode: -1, message: "Something went wrong. Please try again.", code: nil)
        }

        if let data, let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            let message = body.error ?? body.message ?? defaultMessage(for: statusCode)
            let code = body.code ?? body.reason
            return DisplayableError(statusCode: statusCode, message: message, code: code)
        }

        if statusCode == -1 {
            // Transport-level failure — offline, DNS failure, timeout, etc. `underlying` here is
            // the raw URLError/DecodingError the generator wraps rather than an HTTP status.
            return DisplayableError(statusCode: statusCode, message: transportMessage(underlying), code: nil)
        }

        return DisplayableError(statusCode: statusCode, message: defaultMessage(for: statusCode), code: nil)
    }

    private static func transportMessage(_ underlying: Error) -> String {
        if let urlError = underlying as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline — check your connection and try again."
            case .timedOut:
                return "The request timed out. Please try again."
            default:
                return "Couldn't reach Mudbase. Please try again."
            }
        }
        return "Couldn't reach Mudbase. Please try again."
    }

    private static func defaultMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 400: return "That request wasn't valid. Please check the form and try again."
        case 401: return "Your session has expired. Please sign in again."
        case 403: return "You don't have permission to do that."
        case 404: return "That couldn't be found."
        case 409: return "That conflicts with something that already exists."
        case 429: return "Too many attempts — please wait a moment and try again."
        case 500..<600: return "Mudbase is having trouble right now. Please try again shortly."
        default: return "Something went wrong. Please try again."
        }
    }
}

enum MudbaseClientError: Error, Equatable {
    case missingTokenInResponse
    case malformedSessionUser
    case malformedDocument
}
