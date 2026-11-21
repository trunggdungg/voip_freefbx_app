import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:logger/logger.dart';
import 'package:sip_ua/sip_ua.dart';

import '../../../core/config/app_config_provider.dart';
import '../../call/data/call_state_mapper.dart';
import '../../call/domain/call_service.dart';
import '../../call/domain/call_session.dart';
import '../domain/sip_client.dart';
import '../domain/sip_status.dart';
import '../domain/voip_config.dart';
import 'sip_status_mapper.dart';

/// Cài đặt [SipClient] bằng `sip_ua` (SIP over WebSocket, giống softphone web).
class SipUaClient implements SipClient, CallService, SipUaHelperListener {
  SipUaClient({required this.allowBadCertificate, SIPUAHelper? helper})
    : _helper = helper ?? SIPUAHelper() {
    // Mức debug của sip_ua in cả nội dung bản tin SIP, không để lọt ra log.
    _helper.loggingLevel = Level.warning;
    _helper.addSipUaHelperListener(this);
  }

  /// Chấp nhận chứng chỉ WSS tự ký. Chỉ bật ở môi trường dev.
  final bool allowBadCertificate;

  final SIPUAHelper _helper;
  final _controller = StreamController<SipStatus>.broadcast();
  SipStatus _status = const SipStatus.stopped();
  bool _started = false;
  bool _stopping = false;

  // Cuộc gọi hiện tại (M3: gọi đi; M4 sẽ thêm cuộc gọi đến).
  final _callController = StreamController<CallSession?>.broadcast();
  Call? _call;
  CallSession? _session;

  @override
  SipStatus get status => _status;

  @override
  Stream<SipStatus> get statusStream => _controller.stream;

  void _emit(SipStatus next) {
    if (next == _status) return;
    _status = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  Future<void> start(VoipConfig config) async {
    _stopping = false;

    final wsUrl = config.server.websocketUrl;
    if (wsUrl == null) {
      _emit(
        const SipStatus.failed(
          'Máy chủ VoIP trong Odoo chưa có địa chỉ WebSocket (wss://…).',
        ),
      );
      return;
    }
    if (config.server.isLoopback) {
      _emit(
        const SipStatus.failed(
          'Địa chỉ WebSocket là localhost nên điện thoại không kết nối được. '
          'Sửa trong Odoo (VoIP > Máy chủ).',
        ),
      );
      return;
    }

    _emit(const SipStatus.connecting());

    // Giống softphone web: sip:<extension>@<realm hoặc host>
    final domain = config.server.realm ?? config.server.host;
    final settings = UaSettings()
      ..transportType = TransportType.WS
      ..webSocketUrl = wsUrl
      ..webSocketSettings.allowBadCertificate = allowBadCertificate
      ..uri = 'sip:${config.user.username}@$domain'
      ..authorizationUser = config.user.username
      ..password = config.user.password
      ..displayName = config.user.displayName
      ..userAgent = 'EAUT-VoIP-Android'
      ..register = true
      ..register_expires = 300
      // FreePBX/PJSIP mặc định nhận DTMF kiểu RFC 4733 (trong luồng RTP).
      ..dtmfMode = DtmfMode.RFC2833
      ..iceServers = [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ];

    try {
      _started = true;
      await _helper.start(settings);
    } catch (e) {
      _emit(const SipStatus.failed('Không khởi tạo được kết nối SIP.'));
    }
  }

  @override
  Future<void> stop() async {
    _stopping = true;
    if (_session != null && !_session!.isTerminal) {
      _call?.hangup();
    }
    if (_started) {
      _started = false;
      try {
        _helper.stop();
      } catch (_) {
        // Đang dừng: bỏ qua lỗi.
      }
    }
    _emit(const SipStatus.stopped());
  }

  @override
  Future<void> dispose() async {
    await stop();
    _helper.removeSipUaHelperListener(this);
    await _controller.close();
    await _callController.close();
  }

  // ---- CallService ----

  @override
  CallSession? get currentCall => _session;

  @override
  Stream<CallSession?> get callStream => _callController.stream;

  void _emitCall(CallSession? next) {
    _session = next;
    if (!_callController.isClosed) _callController.add(next);
  }

  @override
  Future<void> dial(String number) async {
    if (!_status.isRegistered) {
      throw const CallException('Chưa đăng ký với tổng đài, chưa thể gọi.');
    }
    final active = _session;
    if (active != null && !active.isTerminal) {
      throw const CallException('Đang có một cuộc gọi khác.');
    }
    // Hiện ngay màn hình "Đang gọi…"; sip_ua báo CALL_INITIATION ngay sau đó.
    _emitCall(
      CallSession(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        remoteNumber: number,
        direction: CallDirection.outgoing,
      ),
    );
    final ok = await _helper.call(number, voiceOnly: true);
    if (!ok) {
      _emitCall(null);
      throw const CallException('Không gửi được yêu cầu gọi tới tổng đài.');
    }
  }

  @override
  Future<void> hangup() async {
    final call = _call;
    if (call == null) {
      // Chưa có phiên SIP (đang chờ) mà người dùng đã bấm kết thúc.
      final s = _session;
      if (s != null && !s.isTerminal) {
        _emitCall(
          s.copyWith(
            phase: CallPhase.ended,
            endedAt: DateTime.now(),
            endDetail: 'Đã hủy cuộc gọi',
          ),
        );
      }
      return;
    }
    call.hangup();
  }

  @override
  Future<void> setMuted(bool muted) async {
    final call = _call;
    if (call == null) return;
    muted ? call.mute(true, false) : call.unmute(true, false);
  }

  @override
  Future<void> setHeld(bool held) async {
    final call = _call;
    if (call == null) return;
    held ? call.hold() : call.unhold();
  }

  @override
  Future<void> setSpeaker(bool on) async {
    await Helper.setSpeakerphoneOn(on);
    final s = _session;
    if (s != null) _emitCall(s.copyWith(speakerOn: on));
  }

  Future<void> _resetSpeaker() async {
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {
      // Không có thiết bị âm thanh (vd: khi test): bỏ qua.
    }
  }

  @override
  void sendDtmf(String tone) => _call?.sendDTMF(tone);

  // ---- SipUaHelperListener ----

  @override
  void transportStateChanged(TransportState state) {
    if (_stopping) return;
    _emit(statusFromTransport(state, _status));
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    if (_stopping) return;
    _emit(statusFromRegistration(state, _status));
  }

  @override
  void callStateChanged(Call call, CallState state) {
    // M4 sẽ xử lý cuộc gọi đến. Hiện chỉ theo dõi cuộc gọi đi.
    if (call.direction != Direction.outgoing) return;

    var session = _session;
    if (state.state == CallStateEnum.CALL_INITIATION) {
      // Gắn phiên SIP vào cuộc gọi đang chờ ở dial().
      if (session == null || session.isTerminal) return;
      _call = call;
      _emitCall(
        CallSession(
          id: call.id ?? session.id,
          remoteNumber: session.remoteNumber,
          direction: CallDirection.outgoing,
          speakerOn: session.speakerOn,
        ),
      );
      return;
    }
    if (session == null || _call?.id != call.id) return;

    final next = applyCallState(session, state, now: DateTime.now());
    if (next.isTerminal) {
      _call = null;
      // Trả loa về mặc định (ốp tai) cho cuộc gọi sau.
      unawaited(_resetSpeaker());
    }
    if (!identical(next, session)) _emitCall(next);
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}
}

final sipUaClientProvider = Provider<SipUaClient>((ref) {
  final client = SipUaClient(
    allowBadCertificate: ref.watch(appConfigProvider).allowBadCertificate,
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Cùng một đối tượng đảm nhiệm đăng ký SIP và điều khiển cuộc gọi.
/// Test override hai provider này bằng một client giả.
final sipClientProvider = Provider<SipClient>(
  (ref) => ref.watch(sipUaClientProvider),
);
final callServiceProvider = Provider<CallService>(
  (ref) => ref.watch(sipUaClientProvider),
);
