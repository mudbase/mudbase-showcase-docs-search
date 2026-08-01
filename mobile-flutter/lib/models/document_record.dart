/// Mirrors the web app's `DocumentRecord` (`web/src/types/document.ts`) and
/// the live `documents` collection schema (`title`, `content`, `tags?`,
/// `authorId`, `authorName`).
class DocumentRecord {
  const DocumentRecord({
    required this.id,
    required this.title,
    required this.content,
    this.tags,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DocumentRecord.fromJson(Map<String, dynamic> json) {
    return DocumentRecord(
      id: json['_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      tags: json['tags'] as String?,
      authorId: json['authorId'] as String? ?? '',
      authorName: json['authorName'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }

  final String id;
  final String title;
  final String content;

  /// Comma-separated tags, e.g. "billing,invoices". Optional field on the
  /// collection schema.
  final String? tags;
  final String authorId;
  final String authorName;
  final String createdAt;
  final String updatedAt;

  Map<String, dynamic> toCreateBody() => {
    'title': title,
    'content': content,
    'tags': tags ?? '',
    'authorId': authorId,
    'authorName': authorName,
  };
}
