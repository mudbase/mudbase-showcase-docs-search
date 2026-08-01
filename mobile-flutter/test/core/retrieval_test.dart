import 'package:mudbase_showcase_docs_search/core/retrieval.dart';
import 'package:mudbase_showcase_docs_search/models/document_record.dart';
import 'package:test/test.dart';

DocumentRecord _doc({
  String id = 'doc1',
  String title = '',
  String content = '',
  String? tags,
}) {
  return DocumentRecord(
    id: id,
    title: title,
    content: content,
    tags: tags,
    authorId: '666f6c6c6f77746573746572',
    authorName: 'Test Author',
    createdAt: '2026-08-01T00:00:00.000Z',
    updatedAt: '2026-08-01T00:00:00.000Z',
  );
}

void main() {
  group('countOccurrences', () {
    test('counts case-insensitive substring matches', () {
      expect(
        countOccurrences('Reset your Password with reset link', 'reset'),
        2,
      );
    });

    test('returns 0 for an empty term', () {
      expect(countOccurrences('anything', ''), 0);
    });

    test('returns 0 when the term is absent', () {
      expect(countOccurrences('hello world', 'xyz'), 0);
    });
  });

  group('tokenizeQuery', () {
    test('splits, lowercases, and drops tokens of length <= 2', () {
      expect(tokenizeQuery('How do I reset my password?'), [
        'how',
        'reset',
        'password',
      ]);
    });

    test('deduplicates repeated tokens preserving first-seen order', () {
      expect(tokenizeQuery('reset reset password'), ['reset', 'password']);
    });

    test('returns an empty list for a query with no qualifying tokens', () {
      expect(tokenizeQuery('a to it'), isEmpty);
    });
  });

  group('scoreDocuments', () {
    test('weights title x3, tags x2, content x1', () {
      final titleMatch = _doc(
        id: 'title',
        title: 'password reset guide',
        content: 'irrelevant filler',
      );
      final tagMatch = _doc(
        id: 'tags',
        title: 'unrelated',
        tags: 'password,reset',
        content: 'irrelevant filler',
      );
      final contentMatch = _doc(
        id: 'content',
        title: 'unrelated',
        content: 'password reset password reset',
      );

      final scored = scoreDocuments([
        titleMatch,
        tagMatch,
        contentMatch,
      ], 'password reset');
      final byId = {for (final entry in scored) entry.document.id: entry.score};

      expect(byId['title'], 6); // 2 terms x weight 3
      expect(byId['tags'], 4); // 2 terms x weight 2
      expect(byId['content'], 4); // "password" x2 + "reset" x2, weight 1
    });

    test('drops documents scoring 0 and sorts highest-first', () {
      final noMatch = _doc(
        id: 'no-match',
        title: 'unrelated',
        content: 'nothing here',
      );
      final weak = _doc(
        id: 'weak',
        title: 'billing',
        content: 'password appears once',
      );
      final strong = _doc(
        id: 'strong',
        title: 'password password',
        content: 'password',
      );

      final scored = scoreDocuments([noMatch, weak, strong], 'password');

      expect(scored.map((e) => e.document.id).toList(), ['strong', 'weak']);
    });

    test('returns an empty list when the query has no qualifying tokens', () {
      final doc = _doc(title: 'anything');
      expect(scoreDocuments([doc], 'to'), isEmpty);
    });
  });

  group('matchesSearchTerm', () {
    test('matches on title, content, or tags case-insensitively', () {
      final doc = _doc(
        title: 'Billing FAQ',
        content: 'Refund policy details',
        tags: 'invoices',
      );
      expect(matchesSearchTerm(doc, 'billing'), isTrue);
      expect(matchesSearchTerm(doc, 'REFUND'), isTrue);
      expect(matchesSearchTerm(doc, 'invoices'), isTrue);
      expect(matchesSearchTerm(doc, 'unrelated'), isFalse);
    });

    test('an empty or blank term matches everything', () {
      final doc = _doc(title: 'anything');
      expect(matchesSearchTerm(doc, ''), isTrue);
      expect(matchesSearchTerm(doc, '   '), isTrue);
    });
  });

  group('topCandidates', () {
    test('limits to the requested count and truncates long content', () {
      final longContent = 'x' * 5000;
      final docs = List.generate(
        8,
        (i) => _doc(id: 'doc-$i', title: 'match $i', content: longContent),
      );
      final scored = scoreDocuments(docs, 'match');

      final candidates = topCandidates(scored, limit: 5);

      expect(candidates.length, 5);
      expect(candidates.every((c) => c.content.length == 4000), isTrue);
    });

    test('preserves tags when present, omits when absent', () {
      final withTags = _doc(id: 'a', title: 'match', tags: 'billing');
      final withoutTags = _doc(id: 'b', title: 'match');
      final scored = scoreDocuments([withTags, withoutTags], 'match');

      final candidates = topCandidates(scored);
      final byId = {for (final c in candidates) c.documentId: c};

      expect(byId['a']?.tags, 'billing');
      expect(byId['b']?.tags, isNull);
    });
  });
}
