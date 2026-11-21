import 'package:voip_freefbx_app/core/network/api_exceptions.dart';
import 'package:voip_freefbx_app/core/storage/key_value_store.dart';
import 'package:voip_freefbx_app/features/auth/domain/auth_repository.dart';
import 'package:voip_freefbx_app/features/auth/domain/auth_session.dart';
import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:voip_freefbx_app/core/permissions/permission_service.dart';
import 'package:voip_freefbx_app/features/call/data/ringtone.dart';
import 'package:voip_freefbx_app/features/call/domain/call_service.dart';
import 'package:voip_freefbx_app/features/call/domain/call_session.dart';
import 'package:voip_freefbx_app/features/sip/data/voip_config_repository.dart';
import 'package:voip_freefbx_app/features/sip/domain/sip_client.dart';
import 'package:voip_freefbx_app/features/sip/domain/sip_status.dart';
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

/// SipClient + CallService giả: ghi lại thao tác, cho test đẩy trạng thái vào.
class FakeSipClient implements SipClient, CallService {
  final _controller = StreamController<SipStatus>.broadcast();
  SipStatus _status = const SipStatus.stopped();
  final List<String> startedUsers = [];
  int stopCount = 0;

  void push(SipStatus s) {
    _status = s;
    _controller.add(s);
  }

  @override
  SipStatus get status => _status;

  @override
  Stream<SipStatus> get statusStream => _controller.stream;

  @override
  Future<void> start(VoipConfig config) async {
    startedUsers.add(config.user.username);
    push(const SipStatus.connecting());
  }

  @override
  Future<void> stop() async {
    stopCount++;
    push(const SipStatus.stopped());
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
    await _callController.close();
  }

  // ---- CallService ----
  final _callController = StreamController<CallSession?>.broadcast();
  CallSession? _call;
  final List<String> dialed = [];
  final List<String> dtmf = [];
  int hangups = 0;

  @override
  CallSession? get currentCall => _call;

  @override
  Stream<CallSession?> get callStream => _callController.stream;

  void pushCall(CallSession? s) {
    _call = s;
    _callController.add(s);
  }

  @override
  Future<void> dial(String number) async {
    if (!_status.isRegistered) {
      throw const CallException('Chưa đăng ký với tổng đài, chưa thể gọi.');
    }
    dialed.add(number);
    pushCall(
      CallSession(
        id: 'c${dialed.length}',
        remoteNumber: number,
        direction: CallDirection.outgoing,
      ),
    );
  }

  int answers = 0;
  int rejects = 0;

  @override
  Future<void> answer() async {
    answers++;
    pushCall(
      _call!.copyWith(phase: CallPhase.active, answeredAt: DateTime.now()),
    );
  }

  @override
  Future<void> reject() async {
    rejects++;
    pushCall(
      _call!.copyWith(
        phase: CallPhase.ended,
        endedAt: DateTime.now(),
        endDetail: 'Đã từ chối cuộc gọi',
      ),
    );
  }

  @override
  Future<void> hangup() async {
    hangups++;
    pushCall(
      _call!.copyWith(
        phase: CallPhase.ended,
        endedAt: DateTime.now(),
        endDetail: 'Đã hủy cuộc gọi',
      ),
    );
  }

  @override
  Future<void> setMuted(bool muted) async =>
      pushCall(_call!.copyWith(muted: muted));

  @override
  Future<void> setHeld(bool held) async =>
      pushCall(_call!.copyWith(held: held));

  @override
  Future<void> setSpeaker(bool on) async =>
      pushCall(_call!.copyWith(speakerOn: on));

  @override
  void sendDtmf(String tone) => dtmf.add(tone);
}

class FakePermissionService implements PermissionService {
  FakePermissionService({this.micGranted = true});

  bool micGranted;

  @override
  Future<bool> ensureMicrophone() async => micGranted;

  @override
  Future<PermissionStatus> request(AppPermission p) async =>
      micGranted ? PermissionStatus.granted : PermissionStatus.denied;

  @override
  Future<Map<AppPermission, PermissionStatus>> statuses() async => {
    AppPermission.microphone: micGranted
        ? PermissionStatus.granted
        : PermissionStatus.denied,
    AppPermission.notifications: PermissionStatus.granted,
  };
}

class FakeRingtone implements Ringtone {
  int starts = 0;
  int stops = 0;
  bool get ringing => starts > stops;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> stop() async => stops++;
}
