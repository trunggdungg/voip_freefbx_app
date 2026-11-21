import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/permission_service.dart';
import '../../sip/data/sip_ua_client.dart';
import '../data/ringtone.dart';
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
      _setRinging(false);
    });
    final initial = service.currentCall;
    _setRinging(initial?.isIncomingRinging ?? false);
    return initial;
  }

  bool _ringing = false;

  /// Chỉ đổ chuông khi có cuộc gọi đến đang chờ trả lời.
  void _setRinging(bool ring) {
    if (ring == _ringing) return;
    _ringing = ring;
    final ringtone = ref.read(ringtoneProvider);
    ring ? ringtone.start() : ringtone.stop();
  }

  void _onSession(CallSession? session) {
    _linger?.cancel();
    state = session;
    _setRinging(session?.isIncomingRinging ?? false);
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

  /// Trả lời cuộc gọi đến (cần quyền micro).
  Future<void> answer() async {
    final granted = await ref
        .read(permissionServiceProvider)
        .ensureMicrophone();
    if (!granted) {
      // Không có micro thì nhấc máy cũng vô ích: từ chối để người gọi không chờ mãi.
      await _service.reject();
      throw const CallException(
        'Cần cấp quyền micro để nghe máy. Vào Cài đặt > Ứng dụng > EAUT VoIP > Quyền.',
      );
    }
    _setRinging(false);
    await _service.answer();
  }

  Future<void> reject() async {
    _setRinging(false);
    await _service.reject();
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
