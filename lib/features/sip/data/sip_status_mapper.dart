import 'package:sip_ua/sip_ua.dart';

import '../domain/sip_status.dart';

/// Đổi sự kiện của `sip_ua` thành [SipStatus]. Viết thành hàm thuần để test được.

SipStatus statusFromTransport(TransportState event, SipStatus current) {
  switch (event.state) {
    case TransportStateEnum.CONNECTING:
      return current.isRegistered
          ? const SipStatus.disconnected('Đang kết nối lại…')
          : const SipStatus.connecting();
    case TransportStateEnum.CONNECTED:
      // Đã đăng ký từ trước thì chờ thư viện đăng ký lại, không báo "đã đăng ký" sai.
      return const SipStatus.registering();
    case TransportStateEnum.DISCONNECTED:
      return SipStatus.disconnected(
        _nonEmpty(event.cause?.reason_phrase ?? event.cause?.cause),
      );
    case TransportStateEnum.NONE:
      return current;
  }
}

SipStatus statusFromRegistration(RegistrationState event, SipStatus current) {
  switch (event.state) {
    case RegistrationStateEnum.REGISTERED:
      return const SipStatus.registered();
    case RegistrationStateEnum.REGISTRATION_FAILED:
      return SipStatus.failed(
        describeRegistrationFailure(
          event.cause?.status_code,
          event.cause?.reason_phrase ?? event.cause?.cause,
        ),
      );
    case RegistrationStateEnum.UNREGISTERED:
      return const SipStatus.unregistered();
    case RegistrationStateEnum.NONE:
    case null:
      return current;
  }
}

String describeRegistrationFailure(int? code, String? reason) {
  switch (code) {
    case 401:
    case 403:
      return 'FreePBX từ chối đăng ký (mã $code): sai mật khẩu SIP hoặc '
          'extension không được phép. Kiểm tra voip.user trong Odoo.';
    case 404:
      return 'Extension không tồn tại trên FreePBX (mã 404).';
    case 408:
      return 'FreePBX không phản hồi yêu cầu đăng ký (hết thời gian chờ).';
    case 503:
      return 'FreePBX tạm thời không phục vụ (mã 503).';
  }
  return reason == null || reason.isEmpty
      ? 'Đăng ký thất bại, không rõ nguyên nhân.'
      : 'Đăng ký thất bại: $reason'
            '${code == null ? '' : ' (mã $code)'}.';
}

String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;
