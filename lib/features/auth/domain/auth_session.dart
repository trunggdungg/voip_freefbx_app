/// Phiên đăng nhập hiện tại. Không chứa mật khẩu.
class AuthSession {
  const AuthSession({
    required this.baseUrl,
    required this.database,
    required this.login,
    required this.displayName,
  });

  final String baseUrl;
  final String database;
  final String login;
  final String displayName;
}

/// Thông tin gợi ý sẵn ở màn hình đăng nhập (lần đăng nhập trước).
class LoginPrefill {
  const LoginPrefill({this.baseUrl, this.database, this.login});

  final String? baseUrl;
  final String? database;
  final String? login;
}
