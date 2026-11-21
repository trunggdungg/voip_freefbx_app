import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Kho khóa-giá trị đơn giản. Bản thật dùng secure storage (mã hóa bằng Android Keystore).
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureKeyValueStore implements KeyValueStore {
  const SecureKeyValueStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => const SecureKeyValueStore(),
);

/// Các khóa đang dùng. Mật khẩu Odoo và mật khẩu SIP KHÔNG bao giờ được lưu.
abstract final class StoreKeys {
  static const odooUrl = 'odoo_url';
  static const odooDb = 'odoo_db';
  static const odooLogin = 'odoo_login';
  static const odooUserName = 'odoo_user_name';
  static const sessionId = 'odoo_session_id';
}
