import 'sip_status.dart';
import 'voip_config.dart';

/// Kết nối SIP tới FreePBX. Tách thành interface để test không cần mạng thật.
abstract class SipClient {
  SipStatus get status;
  Stream<SipStatus> get statusStream;

  /// Kết nối WSS và đăng ký extension. Gọi lại sẽ khởi động lại kết nối.
  Future<void> start(VoipConfig config);

  /// Hủy đăng ký và đóng kết nối.
  Future<void> stop();

  Future<void> dispose();
}
