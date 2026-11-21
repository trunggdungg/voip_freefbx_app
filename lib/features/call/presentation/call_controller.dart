import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/permission_service.dart';
import '../../sip/data/sip_ua_client.dart';
import '../domain/call_service.dart';
import '../domain/call_session.dart';

/// Trạng thái cuộc gọi cho giao diện. `null` = không có cuộc gọi.
/// Cuộc gọi đã kết thúc được giữ thêm vài giây để người dùng đọc kết quả.
class CallController extends Notifier<CallSession?> {
  /// Thời gian giữ màn hình kết quả sau khi cuộc gọi kết thúc.
  static const lingerAfterEnd = Duration(seconds: 2);

  Timer? _linger;

  CallService get _service => ref.read(callServiceProvider);

  @override
  CallSession? build() {
    final service = ref.watch(callServiceProvider);
    final sub = service.callStream.listen(_onSession);
    ref.onDispose(() {
      sub.cancel();
      _linger?.cancel();
    });
    return service.currentCall;
  }

  void _onSession(CallSession? session) {
    _linger?.cancel();
    state = session;
    if (session != null && session.isTerminal) {
      _linger = Timer(lingerAfterEnd, () => state = null);
    }
  }

  /// Gọi đi. Ném [CallException] (tiếng Việt) nếu không gọi được.
  Future<void> dial(String raw) async {
    final number = normalizeDialNumber(raw);
    if (number.isEmpty) throw const CallException('Nhập số cần gọi.');

    final current = state;
    if (current != null && !current.isTerminal) {
      throw const CallException('Đang có một cuộc gọi khác.');
    }

    final granted = await ref
        .read(permissionServiceProvider)
        .ensureMicrophone();
    if (!granted) {
      throw const CallException(
        'Cần cấp quyền micro để gọi. Vào Cài đặt > Ứng dụng > EAUT VoIP > Quyền.',
      );
    }
    await _service.dial(number);
  }

  Future<void> hangup() => _service.hangup();
  Future<void> toggleMute() => _service.setMuted(!(state?.muted ?? false));
  Future<void> toggleHold() => _service.setHeld(!(state?.held ?? false));
  Future<void> toggleSpeaker() =>
      _service.setSpeaker(!(state?.speakerOn ?? false));
  void sendDtmf(String tone) => _service.sendDtmf(tone);
}

final callControllerProvider = NotifierProvider<CallController, CallSession?>(
  CallController.new,
);
