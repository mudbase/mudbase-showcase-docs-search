import '../../config/env_config.dart';
import '../../core/mudbase_data_service.dart';
import '../../models/document_record.dart';

class DocumentRepository {
  const DocumentRepository(this._dataService);

  final MudbaseDataService _dataService;

  /// The full library, newest first - fetched once and filtered/scored
  /// client-side (search box substring match, Ask AI keyword ranking)
  /// rather than one query per keystroke, mirroring the reference web app's
  /// `useDocuments` + `useMemo`-filtered list.
  Future<List<DocumentRecord>> list({
    required String token,
    int limit = 100,
  }) async {
    final docs = await _dataService.list(
      EnvConfig.documentsCollectionId,
      token: token,
      sort: '-createdAt',
      limit: limit,
    );
    return docs.map(DocumentRecord.fromJson).toList();
  }

  Future<DocumentRecord?> getById(
    String documentId, {
    required String token,
  }) async {
    final doc = await _dataService.getById(
      EnvConfig.documentsCollectionId,
      documentId,
      token: token,
    );
    return doc == null ? null : DocumentRecord.fromJson(doc);
  }

  /// Signed-in only (enforced both by the UI - see `DocumentFormScreen` -
  /// and server-side by the collection's own role permissions).
  Future<DocumentRecord> create({
    required String token,
    required String title,
    required String content,
    String? tags,
    required String authorId,
    required String authorName,
  }) async {
    final doc = await _dataService.create(EnvConfig.documentsCollectionId, {
      'title': title,
      'content': content,
      'tags': tags ?? '',
      'authorId': authorId,
      'authorName': authorName,
    }, token: token);
    return DocumentRecord.fromJson(doc);
  }

  /// Ownership-scoped edit - the UI only ever shows the edit action to the
  /// document's own author (see `document_detail_screen.dart`), and the
  /// server's own collection permissions are the real enforcement boundary
  /// regardless of what the UI hides.
  Future<DocumentRecord> update({
    required String token,
    required String documentId,
    required String title,
    required String content,
    String? tags,
  }) async {
    final doc = await _dataService.update(
      EnvConfig.documentsCollectionId,
      documentId,
      {'title': title, 'content': content, 'tags': tags ?? ''},
      token: token,
    );
    return DocumentRecord.fromJson(doc);
  }

  Future<void> delete({
    required String token,
    required String documentId,
  }) async {
    await _dataService.delete(
      EnvConfig.documentsCollectionId,
      documentId,
      token: token,
    );
  }
}
