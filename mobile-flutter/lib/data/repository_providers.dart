import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/service_providers.dart';
import 'repositories/document_repository.dart';
import 'repositories/search_log_repository.dart';

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DocumentRepository(ref.watch(mudbaseDataServiceProvider));
});

final searchLogRepositoryProvider = Provider<SearchLogRepository>((ref) {
  return SearchLogRepository(ref.watch(mudbaseDataServiceProvider));
});
