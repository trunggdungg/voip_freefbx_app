import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../data/sip_ua_client.dart';
import '../domain/sip_status.dart';
import '../domain/voip_config.dart';
import 'voip_config_provider.dart';

/// Giữ kết nối SIP theo tài khoản đang đăng nhập:
/// có cấu hình thì kết nối và đăng ký, đăng xuất thì hủy đăng ký.
class SipController extends Notifier<SipStatus> {
  VoipConfig? _config;
  String? _configKey;

  @override
  SipStatus build() {
    final client = ref.watch(sipClientProvider);

    final sub = client.statusStream.listen((s) => state = s);
    ref.onDispose(sub.cancel);

    // Tải xong cấu hình (đăng nhập, hoặc bấm "Thử lại") thì kết nối.
    ref.listen(voipConfigProvider, (_, next) {
      final config = next.value;
      if (config != null) unawaited(_connect(config));
    }, fireImmediately: true);

    // Đăng xuất: hủy đăng ký và quên cấu hình (mật khẩu SIP không giữ lại).
    ref.listen(authControllerProvider, (_, next) {
      if (!next.isLoading && next.value == null) {
        _config = null;
        _configKey = null;
        unawaited(client.stop());
      }
    });

    // Quay lại app mà đang mất kết nối thì thử lại ngay, không chờ vòng thử kế tiếp.
    final lifecycle = AppLifecycleListener(
      onResume: () {
        if (_config != null && client.status.canRetry) reconnect();
      },
    );
    ref.onDispose(lifecycle.dispose);

    return client.status;
  }

  Future<void> _connect(VoipConfig config) async {
    final key =
        '${config.user.username}|${config.user.password}|'
        '${config.server.websocketUrl}|${config.server.realm}';
    final client = ref.read(sipClientProvider);
    // Cùng cấu hình và đang chạy ổn thì không khởi động lại.
    if (key == _configKey &&
        (client.status.isRegistered ||
            client.status.phase == SipPhase.connecting ||
            client.status.phase == SipPhase.registering)) {
      return;
    }
    _config = config;
    _configKey = key;
    await client.start(config);
  }

  /// Người dùng bấm "Kết nối lại".
  void reconnect() {
    final config = _config;
    if (config == null) return;
    unawaited(ref.read(sipClientProvider).start(config));
  }
}

final sipControllerProvider = NotifierProvider<SipController, SipStatus>(
  SipController.new,
);
