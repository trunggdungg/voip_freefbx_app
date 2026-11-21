import 'auth_session.dart';

abstract class AuthRepository {
  /// Khôi phục phiên đã lưu (nếu có). Không gọi mạng.
  Future<AuthSession?> restore();

  Future<AuthSession> login({
    required String baseUrl,
    required String database,
    required String login,
    required String password,
  });

  Future<void> logout();

  Future<LoginPrefill> lastLoginInfo();
}
