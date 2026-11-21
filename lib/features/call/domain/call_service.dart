import 'call_session.dart';

/// Điều khiển cuộc gọi. Tách thành interface để test không cần SIP thật.
abstract class CallService {
  /// Cuộc gọi hiện tại (kể cả vừa kết thúc), null nếu chưa có.
  CallSession? get currentCall;
  Stream<CallSession?> get callStream;

  /// Gọi đi. Ném [CallException] nếu chưa đăng ký hoặc đang có cuộc gọi khác.
  Future<void> dial(String number);

  Future<void> hangup();
  Future<void> setMuted(bool muted);
  Future<void> setHeld(bool held);
  Future<void> setSpeaker(bool on);
  void sendDtmf(String tone);
}
