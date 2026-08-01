import '../../config/env_config.dart';
import '../../core/mudbase_data_service.dart';
import '../../models/search_log_entry.dart';

class SearchLogRepository {
  const SearchLogRepository(this._dataService);

  final MudbaseDataService _dataService;

  Future<List<SearchLogEntry>> recent({
    required String token,
    int limit = 10,
  }) async {
    final docs = await _dataService.list(
      EnvConfig.searchLogCollectionId,
      token: token,
      sort: '-createdAt',
      limit: limit,
    );
    return docs.map(SearchLogEntry.fromJson).toList();
  }

  /// `userId` must be a real ObjectId or omitted entirely - never a
  /// placeholder string (this platform validates any `*Id`-suffixed filter/
  /// write field as a real 24-hex-char ObjectId). Guests searching
  /// anonymously simply omit both `userId` and `userName`.
  Future<SearchLogEntry> log({
    required String token,
    required String queryText,
    required int resultCount,
    String? userId,
    String? userName,
  }) async {
    final doc = await _dataService.create(EnvConfig.searchLogCollectionId, {
      'queryText': queryText,
      'resultCount': resultCount,
      if (userId != null) 'userId': userId,
      if (userName != null) 'userName': userName,
    }, token: token);
    return SearchLogEntry.fromJson(doc);
  }
}
