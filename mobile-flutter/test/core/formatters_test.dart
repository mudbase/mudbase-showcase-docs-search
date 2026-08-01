import 'package:mudbase_showcase_docs_search/core/formatters.dart';
import 'package:test/test.dart';

void main() {
  group('formatRelativeTime', () {
    test('renders "just now" for timestamps under 5 seconds old', () {
      final iso = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 2))
          .toIso8601String();
      expect(formatRelativeTime(iso), 'just now');
    });

    test('renders seconds for under a minute', () {
      final iso = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 30))
          .toIso8601String();
      expect(formatRelativeTime(iso), endsWith('s ago'));
    });

    test('renders minutes for under an hour', () {
      final iso = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 10))
          .toIso8601String();
      expect(formatRelativeTime(iso), endsWith('m ago'));
    });

    test('renders hours for under a day', () {
      final iso = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 5))
          .toIso8601String();
      expect(formatRelativeTime(iso), endsWith('h ago'));
    });

    test('renders days for under a week', () {
      final iso = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 3))
          .toIso8601String();
      expect(formatRelativeTime(iso), endsWith('d ago'));
    });

    test('falls back to a plain date past a week', () {
      final iso = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 30))
          .toIso8601String();
      final result = formatRelativeTime(iso);
      expect(result, isNot(endsWith('ago')));
    });
  });

  group('snippet', () {
    test('returns short text unchanged', () {
      expect(snippet('hello world'), 'hello world');
    });

    test('collapses whitespace', () {
      expect(snippet('hello    \n\n world'), 'hello world');
    });

    test('truncates long text with an ellipsis', () {
      final result = snippet('x' * 200, maxLength: 10);
      expect(result.length, 11); // 10 chars + ellipsis
      expect(result.endsWith('…'), isTrue);
    });
  });

  group('parseTags', () {
    test('splits, trims, and drops empty entries', () {
      expect(parseTags('billing, invoices ,, refunds'), [
        'billing',
        'invoices',
        'refunds',
      ]);
    });

    test('returns an empty list for null or empty input', () {
      expect(parseTags(null), isEmpty);
      expect(parseTags(''), isEmpty);
    });
  });
}
