import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:sip_ua/sip_ua.dart';

import '../../../core/config/app_config_provider.dart';
import '../domain/sip_client.dart';
import '../domain/sip_status.dart';
import '../domain/voip_config.dart';
import 'sip_status_mapper.dart';

/// Cài đặt [SipClient] bằng `sip_ua` (SIP over WebSocket, giống softphone web).
class SipUaClient implements SipClient, SipUaHelperListener {
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
  }

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

  // M3, M4 sẽ xử lý cuộc gọi và tin nhắn.
  @override
  void callStateChanged(Call call, CallState state) {}

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}
}

final sipClientProvider = Provider<SipClient>((ref) {
  final client = SipUaClient(
    allowBadCertificate: ref.watch(appConfigProvider).allowBadCertificate,
  );
  ref.onDispose(client.dispose);
  return client;
});
