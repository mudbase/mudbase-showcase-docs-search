import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env_config.dart';
import 'auth_service.dart';
import 'mudbase_data_service.dart';
import 'mudbase_sdk_provider.dart';
import 'secure_token_storage.dart';

final secureTokenStorageProvider = Provider<SecureTokenStorage>((ref) {
  return SecureTokenStorage();
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(mudbaseSdkProvider), EnvConfig.mudbaseProjectId);
});

final mudbaseDataServiceProvider = Provider<MudbaseDataService>((ref) {
  return MudbaseDataService(
    ref.watch(mudbaseSdkProvider),
    EnvConfig.mudbaseProjectId,
  );
});
