/// Lỗi gọi API, `message` đã là tiếng Việt, hiển thị thẳng cho người dùng.
class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Sai tên đăng nhập / mật khẩu.
class AuthException extends ApiException {
  const AuthException(super.message);
}

/// Phiên đăng nhập hết hạn hoặc bị thu hồi: cần đăng nhập lại.
class SessionExpiredException extends ApiException {
  const SessionExpiredException([
    super.message = 'Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.',
  ]);
}

/// Tài khoản chưa được cấu hình điện thoại VoIP (chưa có `voip.user`).
class VoipNotConfiguredException extends ApiException {
  const VoipNotConfiguredException(super.message);
}
