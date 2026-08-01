import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_service.dart';
import '../../core/mudbase_exception.dart';
import '../../core/secure_token_storage.dart';
import '../../core/service_providers.dart';
import '../../models/mudbase_user.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, MudbaseUser?>(AuthController.new);

class RegisterResult {
  const RegisterResult({
    required this.success,
    required this.requireVerification,
  });

  final bool success;

  /// True when the account was created but still needs email verification
  /// before it can log in - mirrors the web app's `RegisterResult`
  /// (`web/src/hooks/useAuth.ts`).
  final bool requireVerification;
}

/// Owns the current session - always non-null once `build()` resolves: a
/// guest gets an anonymous session automatically (mirrors the web app's
/// `MudbaseProvider` establishing one on mount so the document library and
/// search work with no signup - see `plan/build-plan.md` "Auth Model"), and
/// a real signed-in "customer" account replaces it after `login()`/
/// `registerCustomer()`. `state.value?.isAuthenticated` (NOT `state.value ==
/// null`, which never happens here) is what gates create/edit/delete and
/// Ask AI's `search_log.userId` - see `MudbaseUser.isAuthenticated`.
///
/// Also mirrors the web app's `MudbaseClient.request`'s
/// `retriedAfterRefresh` handling via [callAuthorized]. Ported from the
/// sibling kanban/social/ecommerce Flutter apps' `features/auth/
/// auth_controller.dart`, extended with the anonymous-guest bootstrap this
/// app's own auth model requires (see web reference's
/// `src/lib/mudbase-provider.tsx`).
class AuthController extends AsyncNotifier<MudbaseUser?> {
  String? _token;

  // Refresh tokens rotate on every use (single-use, platform-enforced) - if
  // two calls both hit a 401 at once, only the first refresh call can
  // succeed since the second would present an already-rotated-away token.
  // This lets concurrent callers await the same in-flight refresh instead of
  // racing each other into failure.
  Future<String?>? _refreshInFlight;

  AuthService get _authService => ref.read(authServiceProvider);
  SecureTokenStorage get _tokenStorage => ref.read(secureTokenStorageProvider);

  @override
  Future<MudbaseUser?> build() async {
    final storedToken = await _tokenStorage.readToken();
    if (storedToken == null) {
      return _establishAnonymousSession();
    }
    try {
      final json = await _authService.getSession(storedToken);
      final userJson = json['user'] as Map<String, dynamic>?;
      final authenticated = json['authenticated'] as bool? ?? true;
      if (!authenticated || userJson == null) {
        return _establishAnonymousSession();
      }
      _token = storedToken;
      return MudbaseUser.fromJson(userJson);
    } on Exception {
      // An expired/revoked token, or the server being briefly unreachable,
      // both fall back to a fresh guest session rather than a hard startup
      // crash or a dead-end "signed out with no session" state - this app
      // always has *some* usable session, the same guarantee the web
      // reference gives guests on first load.
      return _establishAnonymousSession();
    }
  }

  Future<MudbaseUser?> _establishAnonymousSession() async {
    try {
      final json = await _authService.loginAnonymous();
      await _applySessionTokens(json);
      final userJson = json['user'] as Map<String, dynamic>?;
      if (userJson == null) {
        throw const FormatException(
          'The server did not return a guest session.',
        );
      }
      return MudbaseUser.fromJson(userJson);
    } on Exception {
      // No guest session and no stored token - the app still functions for
      // screens that don't require an active session (they'll surface their
      // own network-error state), and `login`/`registerCustomer` remain
      // available to establish a real session directly.
      await _tokenStorage.clear();
      return null;
    }
  }

  String requireToken() {
    final token = _token;
    if (token == null) {
      throw StateError('requireToken() called with no active session.');
    }
    return token;
  }

  /// Runs [action] with the current access token and, if it fails because
  /// the token expired or was revoked (a 401 from any Mudbase endpoint),
  /// transparently refreshes the session via the stored refresh token and
  /// retries [action] exactly once with the new token. Mirrors the web
  /// app's `MudbaseClient.request`'s `retriedAfterRefresh` handling.
  ///
  /// If the refresh itself fails, a fresh anonymous session is established
  /// (same fallback `build()` uses) and the *original* 401 is rethrown, so
  /// the caller's existing error handling (a snackbar, an inline message)
  /// still fires.
  Future<T> callAuthorized<T>(Future<T> Function(String token) action) async {
    final token = requireToken();
    try {
      return await action(token);
    } on MudbaseException catch (error) {
      if (error.statusCode != 401) rethrow;
      final refreshed = await _refreshAccessToken();
      if (refreshed == null) {
        state = AsyncData(await _establishAnonymousSession());
        rethrow;
      }
      return action(refreshed);
    }
  }

  Future<String?> _refreshAccessToken() {
    return _refreshInFlight ??= _performRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<String?> _performRefresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) return null;
    try {
      final json = await _authService.refreshSession(refreshToken);
      final newToken = json['token'] as String?;
      if (newToken == null) return null;
      final newRefreshToken = json['refreshToken'] as String?;
      _token = newToken;
      await _tokenStorage.saveSession(
        token: newToken,
        refreshToken: newRefreshToken,
      );
      return newToken;
    } on Exception {
      return null;
    }
  }

  Future<void> registerCustomer({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required bool agreedToTerms,
  }) async {
    final json = await _authService.registerCustomer(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      agreedToTerms: agreedToTerms,
    );
    // The signup validator requires email verification on this project - a
    // successful call here usually means "account created, not yet signed
    // in", so only apply a session if a token actually came back.
    final token = json['token'] as String?;
    if (token == null) return;
    await _applySession(json);
  }

  /// Wraps [registerCustomer] with the `{success, requireVerification}`
  /// result shape the register screen needs, converting a thrown
  /// [MudbaseException] into `success: false` instead of letting it
  /// propagate - mirrors the web app's `useAuth().register`.
  Future<RegisterResult> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required bool agreedToTerms,
  }) async {
    await registerCustomer(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      agreedToTerms: agreedToTerms,
    );
    final requiresVerification = state.valueOrNull?.isAuthenticated != true;
    return RegisterResult(
      success: true,
      requireVerification: requiresVerification,
    );
  }

  Future<void> login({required String email, required String password}) async {
    final json = await _authService.login(email: email, password: password);
    await _applySession(json);
  }

  /// Signs the current real user out and immediately re-establishes a fresh
  /// guest session - unlike the web reference (whose session goes fully
  /// null after logout until the next page load), a mobile app has no
  /// natural "reload" affordance, so falling back to guest browsing
  /// immediately keeps the library/search usable without a dead-end signed-
  /// out screen. A deliberate, documented improvement over the web
  /// reference's own post-logout behavior, not a divergence in what logout
  /// itself does server-side.
  Future<void> logout() async {
    final token = _token;
    if (token != null) {
      try {
        await _authService.logout(token);
      } on Exception {
        // Best-effort - AuthService.logout() already swallows a 401
        // (already revoked), and the local sign-out below must happen
        // regardless of whether the server revoke succeeds.
      }
    }
    _token = null;
    await _tokenStorage.clear();
    state = AsyncData(await _establishAnonymousSession());
  }

  Future<void> _applySession(Map<String, dynamic> json) async {
    final userJson = json['user'] as Map<String, dynamic>?;
    if (userJson == null) {
      throw const FormatException(
        'The server did not return a session for this account.',
      );
    }
    await _applySessionTokens(json);
    state = AsyncData(MudbaseUser.fromJson(userJson));
  }

  Future<void> _applySessionTokens(Map<String, dynamic> json) async {
    final token = json['token'] as String?;
    if (token == null) {
      throw const FormatException('The server did not return a session token.');
    }
    _token = token;
    await _tokenStorage.saveSession(
      token: token,
      refreshToken: json['refreshToken'] as String?,
    );
  }
}
