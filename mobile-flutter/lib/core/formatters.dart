import 'package:intl/intl.dart';

// Ported from the reference web app's `src/lib/utils.ts`.

String formatRelativeTime(String iso) {
  final then = DateTime.parse(iso);
  final now = DateTime.now().toUtc();
  final diffSeconds = now.difference(then.toUtc()).inSeconds;

  if (diffSeconds < 5) return 'just now';
  if (diffSeconds < 60) return '${diffSeconds}s ago';
  final diffMinutes = (diffSeconds / 60).round();
  if (diffMinutes < 60) return '${diffMinutes}m ago';
  final diffHours = (diffMinutes / 60).round();
  if (diffHours < 24) return '${diffHours}h ago';
  final diffDays = (diffHours / 24).round();
  if (diffDays < 7) return '${diffDays}d ago';
  return DateFormat.yMMMd().format(then.toLocal());
}

String formatDateTime(String iso) {
  final date = DateTime.parse(iso).toLocal();
  return DateFormat.yMMMd().add_jm().format(date);
}

/// Builds a short plain-text snippet from document content, for
/// library-card previews.
String snippet(String text, {int maxLength = 160}) {
  final trimmed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.length <= maxLength) return trimmed;
  return '${trimmed.substring(0, maxLength).trimRight()}…';
}

/// Parses the `documents.tags` field (comma-separated string) into a clean
/// list.
List<String> parseTags(String? tags) {
  if (tags == null || tags.isEmpty) return const [];
  return tags
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}
