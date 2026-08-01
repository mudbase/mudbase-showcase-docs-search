/// Mirrors the web app's `SearchLogRecord` (`web/src/types/document.ts`) and
/// the live `search_log` collection schema (`queryText`, `userId?`,
/// `userName?`, `resultCount`).
///
/// `userId` being `null` is a real, distinct state (an anonymous guest's
/// search, or one made before this app finished resolving `userId` must
/// never be a placeholder string - see `SearchLogRepository.log`).
class SearchLogEntry {
  const SearchLogEntry({
    required this.id,
    required this.queryText,
    this.userId,
    this.userName,
    required this.resultCount,
    required this.createdAt,
  });

  factory SearchLogEntry.fromJson(Map<String, dynamic> json) {
    return SearchLogEntry(
      id: json['_id'] as String? ?? '',
      queryText: json['queryText'] as String? ?? '',
      userId: json['userId'] as String?,
      userName: json['userName'] as String?,
      resultCount: (json['resultCount'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  final String id;
  final String queryText;
  final String? userId;
  final String? userName;
  final int resultCount;
  final String createdAt;
}
