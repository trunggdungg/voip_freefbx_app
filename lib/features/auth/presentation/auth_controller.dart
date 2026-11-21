import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/odoo_auth_repository.dart';
import '../domain/auth_session.dart';

/// Trạng thái đăng nhập: `null` = chưa đăng nhập, đang tải = đang khôi phục phiên.
class AuthController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() => ref.read(authRepositoryProvider).restore();

  /// Ném `ApiException` khi thất bại (trạng thái không đổi) để màn đăng nhập hiện lỗi.
  Future<void> login({
    required String baseUrl,
    required String database,
    required String login,
    required String password,
  }) async {
    final session = await ref
        .read(authRepositoryProvider)
        .login(
          baseUrl: baseUrl,
          database: database,
          login: login,
          password: password,
        );
    state = AsyncData(session);
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }

  /// Gọi khi API báo phiên hết hạn.
  Future<void> sessionExpired() => logout();
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);
