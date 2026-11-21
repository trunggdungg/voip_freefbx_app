import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/call/presentation/call_controller.dart';
import '../../features/call/presentation/call_page.dart';
import '../../features/call/presentation/dial_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/home/presentation/home_page.dart';

abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const home = '/';
  static const dial = '/dial';
  static const call = '/call';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // Báo cho router đánh giá lại `redirect` mỗi khi trạng thái đăng nhập đổi.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  late final GoRouter router;

  // Có cuộc gọi thì mở màn hình cuộc gọi; hết cuộc gọi thì quay về màn trước đó.
  // Không dùng địa chỉ hiện tại của router để biết trang đã mở: với trang mở bằng
  // push, go_router vẫn báo địa chỉ cũ, nên tự theo dõi bằng cờ này.
  var callPageOpen = false;
  ref.listen(callControllerProvider, (prev, next) {
    if (next != null && !next.isTerminal && !callPageOpen) {
      callPageOpen = true;
      router
          .push<void>(AppRoutes.call)
          .whenComplete(() => callPageOpen = false);
    } else if (next == null && callPageOpen && router.canPop()) {
      router.pop();
    }
  });

  router = GoRouter(
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
      // Không có cuộc gọi thì không có gì để hiện ở màn hình cuộc gọi.
      if (at == AppRoutes.call && ref.read(callControllerProvider) == null) {
        return AppRoutes.home;
      }
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
        path: AppRoutes.dial,
        builder: (context, state) => const DialPage(),
      ),
      GoRoute(
        path: AppRoutes.call,
        builder: (context, state) => const CallPage(),
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
