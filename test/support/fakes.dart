import 'package:voip_freefbx_app/core/network/api_exceptions.dart';
import 'package:voip_freefbx_app/core/storage/key_value_store.dart';
import 'package:voip_freefbx_app/features/auth/domain/auth_repository.dart';
import 'package:voip_freefbx_app/features/auth/domain/auth_session.dart';
import 'package:voip_freefbx_app/features/sip/data/voip_config_repository.dart';
import 'package:voip_freefbx_app/features/sip/domain/voip_config.dart';

class MemoryStore implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.restored, this.failWith});

  AuthSession? restored;
  ApiException? failWith;
  bool loggedOut = false;
  String? lastPassword;

  @override
  Future<AuthSession?> restore() async => restored;

  @override
  Future<AuthSession> login({
    required String baseUrl,
    required String database,
    required String login,
    required String password,
  }) async {
    lastPassword = password;
    final error = failWith;
    if (error != null) throw error;
    return AuthSession(
      baseUrl: baseUrl,
      database: database,
      login: login,
      displayName: 'Tư vấn viên A',
    );
  }

  @override
  Future<void> logout() async => loggedOut = true;

  @override
  Future<LoginPrefill> lastLoginInfo() async => const LoginPrefill();
}

class FakeVoipConfigRepository implements VoipConfigRepository {
  FakeVoipConfigRepository({this.config, this.error});

  VoipConfig? config;
  ApiException? error;

  @override
  Future<VoipConfig> fetch() async {
    final e = error;
    if (e != null) throw e;
    return config!;
  }
}

VoipConfig sampleConfig({String wss = 'wss://pbx.example.com:8089/ws'}) =>
    VoipConfig(
      server: VoipServerConfig(
        host: 'pbx.example.com',
        websocketUrl: wss,
        realm: 'pbx.example.com',
      ),
      user: const VoipUserConfig(
        username: '1096',
        password: 'secret-sip',
        displayName: 'Tư vấn viên A',
      ),
    );
