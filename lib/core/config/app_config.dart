/// Môi trường chạy của app. Chọn bằng `--dart-define-from-file=config/<env>.json`.
enum AppEnv { dev, prod }

/// Cấu hình theo môi trường, đọc lúc build. Không chứa secret:
/// mật khẩu và token chỉ nằm trong secure storage sau khi đăng nhập.
class AppConfig {
  const AppConfig({
    required this.env,
    required this.defaultOdooUrl,
    required this.defaultDatabase,
    required this.allowBadCertificate,
  });

  final AppEnv env;

  /// Địa chỉ Odoo gợi ý sẵn ở màn hình đăng nhập (người dùng vẫn sửa được).
  final String defaultOdooUrl;
  final String defaultDatabase;

  /// Chấp nhận chứng chỉ WSS/HTTPS không hợp lệ. Chỉ có hiệu lực ở môi trường dev.
  final bool allowBadCertificate;

  bool get isDev => env == AppEnv.dev;

  factory AppConfig.fromEnvironment() {
    const envName = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
    final env = envName == 'prod' ? AppEnv.prod : AppEnv.dev;
    const badCert = bool.fromEnvironment('ALLOW_BAD_CERT');
    return AppConfig(
      env: env,
      defaultOdooUrl: const String.fromEnvironment('ODOO_URL'),
      defaultDatabase: const String.fromEnvironment('ODOO_DB'),
      allowBadCertificate: env == AppEnv.dev && badCert,
    );
  }
}
