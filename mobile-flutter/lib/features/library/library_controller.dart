import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/document_repository.dart';
import '../../data/repository_providers.dart';
import '../../models/document_record.dart';
import '../auth/auth_controller.dart';

final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, List<DocumentRecord>>(
      LibraryController.new,
    );

/// The full document library - fetched once (newest first, up to 100), then
/// filtered client-side by the library screen's search box and scored
/// client-side by the Ask AI screen. Mirrors the reference web app's
/// `useDocuments(DOCUMENTS_COLLECTION_ID, { sort: "-createdAt", limit: 100
/// })` + `useMemo`-filtered list (`web/src/app/page.tsx`).
class LibraryController extends AsyncNotifier<List<DocumentRecord>> {
  DocumentRepository get _repo => ref.read(documentRepositoryProvider);

  @override
  Future<List<DocumentRecord>> build() async {
    // Re-fetch whenever the session changes (guest -> signed-in, sign-out,
    // token refresh) - the library itself is public-read, but a stale
    // anonymous token replaced by a fresh one should not surface an avoidable
    // 401 on the next read.
    ref.watch(authControllerProvider);
    return _fetch();
  }

  Future<List<DocumentRecord>> _fetch() async {
    final authController = ref.read(authControllerProvider.notifier);
    return authController.callAuthorized((token) => _repo.list(token: token));
  }

  Future<void> refresh() async {
    state = const AsyncLoading<List<DocumentRecord>>().copyWithPrevious(state);
    state = await AsyncValue.guard(_fetch);
  }

  /// Signed-in only - the caller (`DocumentFormScreen`) already gates this
  /// behind `user.isAuthenticated`, and the server's own collection
  /// permissions are the real enforcement boundary regardless.
  Future<DocumentRecord> createDocument({
    required String title,
    required String content,
    String? tags,
  }) async {
    final user = ref.read(authControllerProvider).valueOrNull;
    if (user == null || !user.isAuthenticated) {
      throw StateError('createDocument requires a signed-in user.');
    }
    final authController = ref.read(authControllerProvider.notifier);
    final created = await authController.callAuthorized(
      (token) => _repo.create(
        token: token,
        title: title,
        content: content,
        tags: tags,
        authorId: user.id,
        authorName: user.fullName,
      ),
    );
    await refresh();
    return created;
  }

  Future<void> updateDocument({
    required String documentId,
    required String title,
    required String content,
    String? tags,
  }) async {
    final authController = ref.read(authControllerProvider.notifier);
    await authController.callAuthorized(
      (token) => _repo.update(
        token: token,
        documentId: documentId,
        title: title,
        content: content,
        tags: tags,
      ),
    );
    await refresh();
  }

  Future<void> deleteDocument(String documentId) async {
    final authController = ref.read(authControllerProvider.notifier);
    await authController.callAuthorized(
      (token) => _repo.delete(token: token, documentId: documentId),
    );
    await refresh();
  }
}
