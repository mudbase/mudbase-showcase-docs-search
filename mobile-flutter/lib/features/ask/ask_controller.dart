import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/retrieval.dart';
import '../../data/repository_providers.dart';
import '../../models/search_log_entry.dart';
import '../auth/auth_controller.dart';
import '../library/library_controller.dart';

final askControllerProvider = AsyncNotifierProvider<AskController, AskResult?>(
  AskController.new,
);

/// Backs the "Recent searches" list on the Ask AI screen - re-fetches
/// whenever the session changes (same reasoning as
/// `libraryControllerProvider`) and whenever `AskController.ask` logs a new
/// entry (see the `ref.invalidateSelf`-equivalent call there).
final recentSearchesProvider = FutureProvider<List<SearchLogEntry>>((
  ref,
) async {
  ref.watch(authControllerProvider);
  final authController = ref.read(authControllerProvider.notifier);
  return authController.callAuthorized(
    (token) => ref.read(searchLogRepositoryProvider).recent(token: token),
  );
});

/// The result of one Ask AI question: the on-device keyword-ranked
/// citations (title x3/tags x2/content x1 - the identical weights the
/// reference web app's deployed Mudbase Function `docsAskRetrieval` scores
/// with server-side) and whether anything matched at all.
///
/// Deliberately has no `answer` field - see `plan/build-plan.md` "Ask AI
/// architecture" for why this app does not synthesize a natural-language
/// answer: doing so would require either invoking the real Function (which
/// needs an org-scoped API key that must never be embedded in a mobile
/// binary) or calling an LLM directly (same constraint, explicitly called
/// out in this app's own task brief) - both require server-side credential
/// custody this backend-less app does not have. The ranked citations below
/// are real and fully live; the answer-synthesis step is an honestly
/// documented gap, not a faked response.
class AskResult {
  const AskResult({required this.question, required this.ranked});

  final String question;
  final List<ScoredDocument> ranked;

  bool get noMatch => ranked.isEmpty;
}

class AskController extends AsyncNotifier<AskResult?> {
  @override
  Future<AskResult?> build() async => null;

  Future<void> ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;

    state = const AsyncLoading<AskResult?>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final documents = await ref.read(libraryControllerProvider.future);
      final scored = scoreDocuments(documents, trimmed);
      final ranked = scored.take(5).toList(growable: false);

      final user = ref.read(authControllerProvider).valueOrNull;
      final isRealUser = user != null && user.isAuthenticated;
      final authController = ref.read(authControllerProvider.notifier);
      await authController.callAuthorized(
        (token) => ref
            .read(searchLogRepositoryProvider)
            .log(
              token: token,
              queryText: trimmed,
              resultCount: ranked.length,
              userId: isRealUser ? user.id : null,
              userName: isRealUser ? user.fullName : null,
            ),
      );

      ref.invalidate(recentSearchesProvider);
      return AskResult(question: trimmed, ranked: ranked);
    });
  }

  void clear() {
    state = const AsyncData<AskResult?>(null);
  }
}
