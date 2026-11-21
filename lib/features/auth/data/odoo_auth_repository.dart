import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/network/odoo_client.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_session.dart';

class OdooAuthRepository implements AuthRepository {
  OdooAuthRepository(this._client, this._store) {
    _client.onSessionIdChanged = (id) => _store.write(StoreKeys.sessionId, id);
  }

  final OdooClient _client;
  final KeyValueStore _store;

  @override
  Future<AuthSession?> restore() async {
    final url = await _store.read(StoreKeys.odooUrl);
    final sessionId = await _store.read(StoreKeys.sessionId);
    final db = await _store.read(StoreKeys.odooDb);
    final login = await _store.read(StoreKeys.odooLogin);
    if (url == null || sessionId == null || db == null || login == null) {
      return null;
    }
    _client.configure(baseUrl: url, sessionId: sessionId);
    return AuthSession(
      baseUrl: url,
      database: db,
      login: login,
      displayName: await _store.read(StoreKeys.odooUserName) ?? login,
    );
  }

  @override
  Future<AuthSession> login({
    required String baseUrl,
    required String database,
    required String login,
    required String password,
  }) async {
    _client.configure(baseUrl: baseUrl);
    final result = await _client.rpc('/web/session/authenticate', {
      'db': database,
      'login': login,
      'password': password,
    });

    final uid = result is Map ? result['uid'] : null;
    if (uid is! int) {
      throw const AuthException('Sai tên đăng nhập hoặc mật khẩu.');
    }
    final sessionId = _client.sessionId;
    if (sessionId == null) {
      throw const ApiException(
        'Đăng nhập được nhưng máy chủ không cấp phiên làm việc.',
      );
    }

    final name = '${(result as Map)['name'] ?? login}';
    await _store.write(StoreKeys.odooUrl, baseUrl);
    await _store.write(StoreKeys.odooDb, database);
    await _store.write(StoreKeys.odooLogin, login);
    await _store.write(StoreKeys.odooUserName, name);
    await _store.write(StoreKeys.sessionId, sessionId);
    return AuthSession(
      baseUrl: baseUrl,
      database: database,
      login: login,
      displayName: name,
    );
  }

  @override
  Future<void> logout() async {
    try {
      await _client.rpc('/web/session/destroy');
    } on ApiException {
      // Mất mạng hay phiên đã hết hạn: vẫn xóa dữ liệu cục bộ.
    }
    _client.clearSession();
    // Giữ lại url/db/login để lần sau đăng nhập nhanh hơn.
    await _store.delete(StoreKeys.sessionId);
  }

  @override
  Future<LoginPrefill> lastLoginInfo() async => LoginPrefill(
    baseUrl: await _store.read(StoreKeys.odooUrl),
    database: await _store.read(StoreKeys.odooDb),
    login: await _store.read(StoreKeys.odooLogin),
  );
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => OdooAuthRepository(
    ref.watch(odooClientProvider),
    ref.watch(keyValueStoreProvider),
  ),
);
