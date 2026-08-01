import 'package:dio/dio.dart';

/// Mirrors the web app's `MudbaseError` (`web/src/lib/mudbase.ts`) - a typed
/// error surface for every Mudbase HTTP call so screens can show the
/// server's own message instead of a generic "something went wrong". Ported
/// verbatim from the sibling kanban/social/ecommerce Flutter apps'
/// `core/mudbase_exception.dart`.
class MudbaseException implements Exception {
  const MudbaseException(this.message, this.statusCode, [this.code]);

  final String message;
  final int statusCode;
  final String? code;

  /// Builds a [MudbaseException] from a failed [DioException], reading the
  /// server's `{ error }` / `{ message }` / `{ code }` JSON body when present
  /// (the shape every Mudbase error response uses - e.g. an insufficient-
  /// permission write returns `{"error":"Insufficient permissions", ...}`)
  /// and falling back to the transport-level message for network failures
  /// that never reached a response (timeout, no connectivity, DNS failure).
  factory MudbaseException.fromDioException(DioException error) {
    final response = error.response;
    if (response == null) {
      return MudbaseException(_networkMessage(error), 0);
    }
    final data = response.data;
    if (data is Map<String, dynamic>) {
      final message =
          data['error'] as String? ??
          data['message'] as String? ??
          'Request failed (${response.statusCode})';
      final code = data['code'] as String? ?? data['reason'] as String?;
      return MudbaseException(message, response.statusCode ?? 0, code);
    }
    return MudbaseException(
      'Request failed (${response.statusCode})',
      response.statusCode ?? 0,
    );
  }

  static String _networkMessage(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'The request timed out. Check your connection and try again.',
      DioExceptionType.connectionError =>
        "Couldn't reach the server. Check your connection and try again.",
      _ => error.message ?? 'Something went wrong. Please try again.',
    };
  }

  @override
  String toString() => message;
}
