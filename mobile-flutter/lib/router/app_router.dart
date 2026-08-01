import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/ask/ask_screen.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/document_detail/document_detail_screen.dart';
import '../features/document_form/document_form_screen.dart';
import '../features/library/library_screen.dart';
import '../features/shell/home_shell.dart';

/// Bridges Riverpod's [authControllerProvider] to go_router's
/// `refreshListenable` - go_router only re-evaluates `redirect` on
/// navigation or when this notifies, so the splash-screen session bootstrap
/// resolving (guest or real session) still re-runs the redirect logic below
/// without an intervening navigation event.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (previous, next) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/documents/new',
        builder: (context, state) => const DocumentFormScreen(),
      ),
      GoRoute(
        path: '/documents/:id',
        builder: (context, state) =>
            DocumentDetailScreen(documentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/documents/:id/edit',
        builder: (context, state) =>
            DocumentFormScreen(documentId: state.pathParameters['id']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ask',
                builder: (context, state) => const AskScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// This app always has *some* usable session (an anonymous guest session is
/// established automatically - see `AuthController._establishAnonymousSession`)
/// so, unlike the sibling kanban port, there is no hard "must sign in"
/// redirect: the only gate this router enforces is holding on the splash
/// screen until that bootstrap resolves at least once.
String? _redirect(Ref ref, GoRouterState state) {
  final authState = ref.read(authControllerProvider);
  final location = state.matchedLocation;

  if (authState.isLoading && authState.valueOrNull == null) {
    return location == '/splash' ? null : '/splash';
  }

  if (location == '/splash') return '/';

  return null;
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
