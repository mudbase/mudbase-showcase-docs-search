import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Auth token persistence - Keychain on iOS, EncryptedSharedPreferences on
/// Android. Hard project security rule: the auth token is never written to
/// `SharedPreferences` (or any other plaintext store) - a mobile app's local
/// storage is a materially different threat model (device compromise,
/// shared devices, backup extraction) than the web reference app's
/// `localStorage`. Holds the anonymous-guest token just as carefully as a
/// real signed-in user's token - both are real, usable session credentials.
/// Ported verbatim from the sibling kanban/social/ecommerce Flutter apps'
/// `core/secure_token_storage.dart`.
class SecureTokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  static const String _tokenKey = 'mudbase_auth_token';
  static const String _refreshTokenKey = 'mudbase_refresh_token';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> saveSession({
    required String token,
    String? refreshToken,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    if (refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
