import 'package:mudbase_showcase_docs_search/models/search_log_entry.dart';
import 'package:test/test.dart';

void main() {
  group('SearchLogEntry.fromJson', () {
    test('parses a signed-in user\'s search log entry', () {
      final entry = SearchLogEntry.fromJson({
        '_id': 'log1',
        'queryText': 'How do I reset my password?',
        'userId': '6a6d409a51703cd1071b46fe',
        'userName': 'Docs Member',
        'resultCount': 3,
        'createdAt': '2026-08-01T00:00:00.000Z',
      });

      expect(entry.queryText, 'How do I reset my password?');
      expect(entry.userId, '6a6d409a51703cd1071b46fe');
      expect(entry.resultCount, 3);
    });

    test(
      'userId/userName are null for an anonymous guest search, never placeholders',
      () {
        final entry = SearchLogEntry.fromJson({
          '_id': 'log2',
          'queryText': 'billing question',
          'resultCount': 0,
          'createdAt': '2026-08-01T00:00:00.000Z',
        });

        expect(entry.userId, isNull);
        expect(entry.userName, isNull);
      },
    );

    test('resultCount coerces a numeric JSON value to int', () {
      final entry = SearchLogEntry.fromJson({'resultCount': 4.0});
      expect(entry.resultCount, 4);
    });
  });
}
