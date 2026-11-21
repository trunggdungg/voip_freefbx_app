import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/home/presentation/home_page.dart';

abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const home = '/';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // Báo cho router đánh giá lại `redirect` mỗi khi trạng thái đăng nhập đổi.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final at = state.matchedLocation;
      if (auth.isLoading) {
        return at == AppRoutes.splash ? null : AppRoutes.splash;
      }
      final loggedIn = auth.value != null;
      if (!loggedIn) return at == AppRoutes.login ? null : AppRoutes.login;
      return (at == AppRoutes.login || at == AppRoutes.splash)
          ? AppRoutes.home
          : null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomePage(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
