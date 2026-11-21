import 'package:flutter_test/flutter_test.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:voip_freefbx_app/features/sip/data/sip_status_mapper.dart';
import 'package:voip_freefbx_app/features/sip/domain/sip_status.dart';

void main() {
  const idle = SipStatus.stopped();

  group('transport', () {
    test('kết nối → đăng ký → đã đăng ký', () {
      var s = statusFromTransport(
        TransportState(TransportStateEnum.CONNECTING),
        idle,
      );
      expect(s.phase, SipPhase.connecting);
      s = statusFromTransport(TransportState(TransportStateEnum.CONNECTED), s);
      expect(s.phase, SipPhase.registering);
      s = statusFromRegistration(
        RegistrationState(state: RegistrationStateEnum.REGISTERED),
        s,
      );
      expect(s.isRegistered, isTrue);
    });

    test(
      'đang đăng ký mà mất WebSocket thì báo mất kết nối, có thể thử lại',
      () {
        const registered = SipStatus.registered();
        final s = statusFromTransport(
          TransportState(TransportStateEnum.DISCONNECTED),
          registered,
        );
        expect(s.phase, SipPhase.disconnected);
        expect(s.canRetry, isTrue);
      },
    );

    test('kết nối lại sau khi đã đăng ký không báo "đã đăng ký" sai', () {
      final s = statusFromTransport(
        TransportState(TransportStateEnum.CONNECTING),
        const SipStatus.registered(),
      );
      expect(s.phase, SipPhase.disconnected);
      final s2 = statusFromTransport(
        TransportState(TransportStateEnum.CONNECTED),
        s,
      );
      expect(s2.phase, SipPhase.registering);
    });

    test('NONE giữ nguyên trạng thái hiện tại', () {
      const cur = SipStatus.registered();
      expect(
        statusFromTransport(TransportState(TransportStateEnum.NONE), cur),
        cur,
      );
    });
  });

  group('đăng ký', () {
    test('thất bại không rõ nguyên nhân', () {
      final s = statusFromRegistration(
        RegistrationState(state: RegistrationStateEnum.REGISTRATION_FAILED),
        idle,
      );
      expect(s.phase, SipPhase.failed);
      expect(s.detail, contains('không rõ nguyên nhân'));
    });

    test('hủy đăng ký', () {
      expect(
        statusFromRegistration(
          RegistrationState(state: RegistrationStateEnum.UNREGISTERED),
          idle,
        ),
        const SipStatus.unregistered(),
      );
    });
  });

  group('mô tả lỗi đăng ký', () {
    test('401/403: sai mật khẩu hoặc extension bị từ chối', () {
      expect(
        describeRegistrationFailure(403, 'Forbidden'),
        contains('từ chối'),
      );
      expect(describeRegistrationFailure(401, null), contains('mật khẩu SIP'));
    });
    test('404, 408, 503', () {
      expect(describeRegistrationFailure(404, null), contains('không tồn tại'));
      expect(
        describeRegistrationFailure(408, null),
        contains('không phản hồi'),
      );
      expect(describeRegistrationFailure(503, null), contains('503'));
    });
    test('mã lạ kèm lý do', () {
      expect(
        describeRegistrationFailure(486, 'Busy Here'),
        'Đăng ký thất bại: Busy Here (mã 486).',
      );
    });
  });
}
