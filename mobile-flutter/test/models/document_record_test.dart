import 'package:mudbase_showcase_docs_search/models/document_record.dart';
import 'package:test/test.dart';

void main() {
  group('DocumentRecord.fromJson', () {
    test('parses a full document', () {
      final doc = DocumentRecord.fromJson({
        '_id': '6a6d5000000000000000aaaa',
        'title': 'Password Reset Guide',
        'content': 'Step by step instructions.',
        'tags': 'auth,password',
        'authorId': '6a6d409a51703cd1071b46fe',
        'authorName': 'Docs Member',
        'createdAt': '2026-08-01T00:00:00.000Z',
        'updatedAt': '2026-08-01T00:00:00.000Z',
      });

      expect(doc.id, '6a6d5000000000000000aaaa');
      expect(doc.title, 'Password Reset Guide');
      expect(doc.tags, 'auth,password');
    });

    test('tags is null when absent, not an empty string', () {
      final doc = DocumentRecord.fromJson({
        '_id': 'x',
        'title': 't',
        'content': 'c',
        'authorId': 'a',
        'authorName': 'n',
      });
      expect(doc.tags, isNull);
    });

    test('missing string fields default to empty string, never null', () {
      final doc = DocumentRecord.fromJson(const {});
      expect(doc.id, '');
      expect(doc.title, '');
      expect(doc.content, '');
      expect(doc.authorId, '');
      expect(doc.authorName, '');
    });
  });

  group('DocumentRecord.toCreateBody', () {
    test('always sends tags as a string, defaulting to empty', () {
      const doc = DocumentRecord(
        id: 'x',
        title: 'Title',
        content: 'Content',
        authorId: 'a',
        authorName: 'n',
        createdAt: '',
        updatedAt: '',
      );
      expect(doc.toCreateBody()['tags'], '');
    });
  });
}
