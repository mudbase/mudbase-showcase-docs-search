// ignore_for_file: avoid_print
//
// Standalone, non-Flutter smoke test that exercises this app's own
// `lib/core/*`/`lib/data/*` layer - the exact classes `AuthController` and
// `LibraryController` call - directly against the real, live
// `cloud.mudbase.dev` project. No Flutter SDK/device is required to run
// this: `AuthService`, `MudbaseDataService`, and every repository only
// depend on `dio`/`mudbase_sdk`, never `package:flutter`. Mirrors the
// sibling kanban/social/ecommerce Flutter apps' `tool/manual_test.dart` in
// structure and intent.
//
// Run with (values are this showcase's real, already-provisioned ids - not
// secrets, same ones baked into `dart_define.example.json` and
// `lib/config/env_config.dart`'s own defaults):
//
//   dart run tool/manual_test.dart
//
// NOTE (environment constraint, documented in plan/build-plan.md "Testing
// Note"): this build environment has no Flutter SDK installed, and this
// project's pubspec.yaml depends on `flutter: sdk: flutter` - so `dart pub
// get`/`dart run` cannot resolve *this* package's dependencies here
// directly. This script was actually executed via the scratch-package
// technique documented there (copying the Flutter-free subset of `lib/`
// into a throwaway package with a `flutter`-free `pubspec.yaml`) - see that
// section for the real, live output this produced.
//
// Exits with a non-zero status if any *required* step fails.
import 'dart:io';

import 'package:mudbase_sdk/mudbase_sdk.dart';
import 'package:mudbase_showcase_docs_search/config/env_config.dart';
import 'package:mudbase_showcase_docs_search/core/auth_service.dart';
import 'package:mudbase_showcase_docs_search/core/mudbase_data_service.dart';
import 'package:mudbase_showcase_docs_search/core/mudbase_exception.dart';
import 'package:mudbase_showcase_docs_search/core/retrieval.dart';
import 'package:mudbase_showcase_docs_search/data/repositories/document_repository.dart';
import 'package:mudbase_showcase_docs_search/data/repositories/search_log_repository.dart';
import 'package:mudbase_showcase_docs_search/models/document_record.dart';

// The already-verified demo account named in this app's own task brief -
// this script only ever logs in, never registers.
const _memberEmail = 'docs.member.demo@gmail.com';
const _memberPassword = 'DemoTest123!';

// Distinctly-named test documents so this run's writes are easy to spot and
// clean up, rather than colliding with any documents already seeded by the
// reference web app's own smoke test (see ../web/plan/build-plan.md).
const _testTitle = 'Flutter smoke test: Password Reset Guide';
const _testContent =
    'To reset your password, open Settings > Security > Reset Password and '
    'follow the emailed link. The link expires after 15 minutes.';
const _testTags = 'auth,password,reset';

int _passed = 0;
int _failed = 0;

Future<bool> _step(String name, Future<void> Function() body) async {
  stdout.write('- $name ... ');
  try {
    await body();
    stdout.writeln('PASS');
    _passed++;
    return true;
  } on Object catch (error) {
    stdout.writeln('FAIL ($error)');
    _failed++;
    return false;
  }
}

Future<void> _requireStep(String name, Future<void> Function() body) async {
  final ok = await _step(name, body);
  if (ok) return;
  print('');
  print(
    'Stopping: "$name" failed and every remaining step depends on it - '
    'see the FAIL line above for the real cause.',
  );
  print('Passed: $_passed, Failed: $_failed');
  exit(1);
}

void main() async {
  print('Mudbase Showcase Docs Search (Flutter) - live manual smoke test');
  print('Base URL: ${EnvConfig.mudbaseBaseUrl}');
  print('Project:  ${EnvConfig.mudbaseProjectId}');
  print('');

  final sdk = MudbaseSdk(basePathOverride: EnvConfig.mudbaseBaseUrl);
  final auth = AuthService(sdk, EnvConfig.mudbaseProjectId);
  final data = MudbaseDataService(sdk, EnvConfig.mudbaseProjectId);
  final documents = DocumentRepository(data);
  final searchLog = SearchLogRepository(data);

  String? guestToken;
  String? memberToken;
  String? memberRefreshToken;
  String? memberId;
  String? testDocumentId;

  await _requireStep('create an anonymous guest session', () async {
    final json = await auth.loginAnonymous();
    guestToken = json['token'] as String?;
    final user = json['user'] as Map<String, dynamic>?;
    if (guestToken == null) {
      throw StateError('Anonymous session missing token: $json');
    }
    final isAnonymous = user?['isAnonymous'] as bool?;
    if (isAnonymous != true) {
      throw StateError('expected isAnonymous true, got $isAnonymous');
    }
  });

  await _requireStep(
    'guest reads the documents collection with zero prior data',
    () async {
      // Proves the anonymous session is a real, usable read credential -
      // confirmed live elsewhere that every collection read 401s with no
      // auth at all, even with the project's own publishable key.
      await documents.list(token: guestToken!);
    },
  );

  await _step(
    'guest attempts to create a document (observing actual server behavior, '
    'not assuming it)',
    () async {
      try {
        final created = await documents.create(
          token: guestToken!,
          title: 'Guest write attempt - should not persist if rejected',
          content: 'probe',
          authorId: 'guest',
          authorName: 'Guest',
        );
        // If this succeeds, the platform's single default "customer" role
        // grants full CRUD to anonymous sessions too, and this app's own
        // "signed-in only" gate on document creation is a UI-level policy
        // choice, not a server-enforced one - clean up immediately either
        // way so it doesn't pollute the real library.
        await documents.delete(token: guestToken!, documentId: created.id);
        print('  (observed: guest WRITE SUCCEEDED - cleaned up immediately)');
      } on MudbaseException catch (error) {
        print(
          '  (observed: guest write REJECTED - status ${error.statusCode})',
        );
      }
    },
  );

  await _requireStep('login as the demo member', () async {
    final json = await auth.login(
      email: _memberEmail,
      password: _memberPassword,
    );
    memberToken = json['token'] as String?;
    memberRefreshToken = json['refreshToken'] as String?;
    final user = json['user'] as Map<String, dynamic>?;
    memberId = user?['id'] as String? ?? user?['_id'] as String?;
    final customRole = user?['customRole'] as String?;
    if (memberToken == null || memberId == null) {
      throw StateError('Member session missing token/id: $json');
    }
    if (customRole != 'customer') {
      throw StateError('expected customRole "customer", got "$customRole"');
    }
  });

  await _requireStep('member creates a test document', () async {
    final created = await documents.create(
      token: memberToken!,
      title: _testTitle,
      content: _testContent,
      tags: _testTags,
      authorId: memberId!,
      authorName: 'Docs Member',
    );
    testDocumentId = created.id;
    if (created.title != _testTitle) {
      throw StateError('title was not persisted on create');
    }
  });

  await _step('member reads the new document back by id', () async {
    final fetched = await documents.getById(
      testDocumentId!,
      token: memberToken!,
    );
    if (fetched == null || fetched.content != _testContent) {
      throw StateError('fetched document content did not match');
    }
  });

  await _step('the library list includes the new document', () async {
    final all = await documents.list(token: memberToken!);
    final found = all.any((d) => d.id == testDocumentId);
    if (!found) throw StateError('new document not found in library list');
  });

  const updatedContent =
      'Updated during the live smoke test: reset links now expire after 30 minutes.';
  await _step('member edits the document (ownership-scoped)', () async {
    final updated = await documents.update(
      token: memberToken!,
      documentId: testDocumentId!,
      title: _testTitle,
      content: updatedContent,
      tags: _testTags,
    );
    if (updated.content != updatedContent) {
      throw StateError('content was not updated');
    }
  });

  await _step(
    'client-side retrieval scoring ranks the real fetched document correctly',
    () async {
      final all = await documents.list(token: memberToken!);
      final scored = scoreDocuments(all, 'How do I reset my password?');
      if (scored.isEmpty) {
        throw StateError('expected at least one scored match');
      }
      // This is a shared, live demo project - the reference web app's own
      // smoke test already seeded a document literally titled "Password
      // Reset Guide" (see ../web/plan/build-plan.md), so asserting *rank
      // 1* would be a false negative whenever that pre-existing document's
      // title happens to score higher than this run's own test document.
      // The behavior this step actually needs to prove - the on-device
      // Dart port of the scoring algorithm finds and positively scores the
      // real document this run created - holds regardless of what else is
      // in the shared collection.
      final match = scored.where((s) => s.document.id == testDocumentId);
      if (match.isEmpty) {
        throw StateError(
          'expected the test document to appear in scored results, found '
          '${scored.length} other matches instead',
        );
      }
      if (match.first.score <= 0) {
        throw StateError('expected a positive score, got ${match.first.score}');
      }
      final DocumentRecord top = scored.first.document;
      print(
        '  (observed: top-ranked match is "${top.title}", score ${scored.first.score})',
      );
    },
  );

  await _step(
    'guest (a different identity) attempts to edit the member\'s document '
    '(observing actual behavior)',
    () async {
      try {
        await documents.update(
          token: guestToken!,
          documentId: testDocumentId!,
          title: 'Guest tampering attempt',
          content: 'should this be allowed?',
        );
        print('  (observed: guest edit of another user\'s document SUCCEEDED)');
        // Restore the member's content so later steps see the expected state.
        await documents.update(
          token: memberToken!,
          documentId: testDocumentId!,
          title: _testTitle,
          content: updatedContent,
          tags: _testTags,
        );
      } on MudbaseException catch (error) {
        print('  (observed: guest edit REJECTED - status ${error.statusCode})');
      }
    },
  );

  await _step(
    'member logs a search_log entry with a real userId (never a placeholder)',
    () async {
      final logged = await searchLog.log(
        token: memberToken!,
        queryText: 'How do I reset my password?',
        resultCount: 1,
        userId: memberId,
        userName: 'Docs Member',
      );
      if (logged.userId != memberId) {
        throw StateError('search_log entry did not persist the real userId');
      }
    },
  );

  await _step('the recent searches list includes the new entry', () async {
    final recent = await searchLog.recent(token: memberToken!);
    final found = recent.any(
      (e) => e.queryText == 'How do I reset my password?',
    );
    if (!found) throw StateError('search_log entry not found in recent list');
  });

  await _step(
    'POST /api/auth/refresh returns a new, distinct token pair',
    () async {
      if (memberRefreshToken == null) {
        throw StateError('no refresh token was issued at login');
      }
      final refreshed = await auth.refreshSession(memberRefreshToken!);
      final newToken = refreshed['token'] as String?;
      if (newToken == null || newToken == memberToken) {
        throw StateError('refresh did not return a distinct new access token');
      }
      // Prove the new token is actually usable with a real authenticated call.
      await documents.list(token: newToken);
      memberToken = newToken;
    },
  );

  await _step('an invalid access token is rejected with a real 401', () async {
    try {
      await data.list(
        EnvConfig.documentsCollectionId,
        token: 'not-a-real-token',
        limit: 1,
      );
      throw StateError('expected a 401, request unexpectedly succeeded');
    } on MudbaseException catch (error) {
      if (error.statusCode != 401) {
        throw StateError('expected statusCode 401, got ${error.statusCode}');
      }
    }
  });

  await _step('cleanup: member deletes the test document', () async {
    final id = testDocumentId;
    if (id == null) return;
    await documents.delete(token: memberToken!, documentId: id);
  });

  await _step('cleanup: deleted document 404s on read', () async {
    final id = testDocumentId;
    if (id == null) return;
    final fetched = await documents.getById(id, token: memberToken!);
    if (fetched != null)
      throw StateError('document still readable after delete');
  });

  await _step('sign out (best-effort server-side revoke)', () async {
    await auth.logout(memberToken!);
    await auth.logout(guestToken!);
  });

  print('');
  print('Passed: $_passed, Failed: $_failed');
  if (_failed > 0) exit(1);
}
