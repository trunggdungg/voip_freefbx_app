import 'package:sip_ua/sip_ua.dart';

import '../domain/call_session.dart';

/// Áp một sự kiện cuộc gọi của `sip_ua` lên [CallSession]. Hàm thuần để test được.
CallSession applyCallState(
  CallSession current,
  CallState event, {
  required DateTime now,
}) {
  // Đã kết thúc thì bỏ qua mọi sự kiện đến muộn.
  if (current.isTerminal) return current;

  switch (event.state) {
    case CallStateEnum.PROGRESS:
      return current.phase == CallPhase.dialing
          ? current.copyWith(phase: CallPhase.ringing)
          : current;
    case CallStateEnum.ACCEPTED:
    case CallStateEnum.CONFIRMED:
      return current.answeredAt != null
          ? current
          : current.copyWith(phase: CallPhase.active, answeredAt: now);
    case CallStateEnum.HOLD:
      // Chỉ quan tâm mình giữ máy, không phải bên kia giữ.
      return event.originator == Originator.local
          ? current.copyWith(held: true)
          : current;
    case CallStateEnum.UNHOLD:
      return event.originator == Originator.local
          ? current.copyWith(held: false)
          : current;
    case CallStateEnum.MUTED:
      return event.audio == true ? current.copyWith(muted: true) : current;
    case CallStateEnum.UNMUTED:
      return event.audio == true ? current.copyWith(muted: false) : current;
    case CallStateEnum.FAILED:
      return _terminal(current, event, now, failed: true);
    case CallStateEnum.ENDED:
      return _terminal(current, event, now, failed: false);
    case CallStateEnum.NONE:
    case CallStateEnum.STREAM:
    case CallStateEnum.CONNECTING:
    case CallStateEnum.CALL_INITIATION:
    case CallStateEnum.REFER:
      return current;
  }
}

/// Mô tả lý do kết thúc bằng tiếng Việt từ mã SIP / chuỗi nguyên nhân của sip_ua.
String describeCallEnd(int? code, String? reason) {
  switch (code) {
    case 486:
    case 600:
      return 'Máy bận';
    case 487:
      return 'Đã hủy cuộc gọi';
    case 404:
      return 'Số không tồn tại';
    case 484:
      return 'Số không đầy đủ';
    case 480:
    case 503:
      return 'Số tạm thời không liên lạc được';
    case 603:
      return 'Người nhận từ chối cuộc gọi';
    case 408:
      return 'Không có phản hồi từ tổng đài';
    case 403:
      return 'Không có quyền gọi số này (kiểm tra outbound route trên FreePBX)';
    case 488:
      return 'Không thương lượng được âm thanh (kiểm tra cấu hình WebRTC/codec)';
  }
  switch (reason) {
    case 'Canceled':
      return 'Đã hủy cuộc gọi';
    case 'Busy':
      return 'Máy bận';
    case 'Rejected':
      return 'Người nhận từ chối cuộc gọi';
    case 'Not Found':
      return 'Số không tồn tại';
    case 'Unavailable':
      return 'Số tạm thời không liên lạc được';
    case 'Request Timeout':
      return 'Không có phản hồi từ tổng đài';
    case 'User Denied Media Access':
      return 'Chưa cấp quyền micro cho ứng dụng';
    case 'WebRTC Error':
      return 'Lỗi âm thanh (WebRTC)';
    case 'Bye':
    case 'Terminated':
    case null:
      return 'Cuộc gọi kết thúc';
  }
  return 'Cuộc gọi kết thúc ($reason${code == null ? '' : ', mã $code'})';
}

CallSession _terminal(
  CallSession current,
  CallState event,
  DateTime now, {
  required bool failed,
}) {
  final code = event.cause?.status_code;
  final reason = event.cause?.reason_phrase ?? event.cause?.cause;

  // Cuộc gọi đến mà mình chưa nghe máy.
  if (current.direction == CallDirection.incoming &&
      current.answeredAt == null) {
    final lower = (reason ?? '').toLowerCase();
    // FreePBX báo "Call completed elsewhere" khi người khác trong nhóm đã nghe máy.
    if (lower.contains('elsewhere') || lower.contains('cause=200')) {
      return current.copyWith(
        phase: CallPhase.ended,
        endedAt: now,
        endDetail: 'Đã được máy khác trả lời',
      );
    }
    // Chính mình từ chối.
    if (event.originator == Originator.local) {
      return current.copyWith(
        phase: CallPhase.ended,
        endedAt: now,
        endDetail: 'Đã từ chối cuộc gọi',
      );
    }
    // Bên gọi gác máy (hoặc hết giờ chờ) khi mình chưa kịp nghe: cuộc gọi nhỡ.
    return current.copyWith(
      phase: CallPhase.ended,
      endedAt: now,
      endDetail: 'Cuộc gọi nhỡ',
      missed: true,
    );
  }

  if (failed) {
    // Mình hủy khi đang đổ chuông không phải là "thất bại".
    final cancelled = code == 487 || reason == 'Canceled';
    return current.copyWith(
      phase: cancelled ? CallPhase.ended : CallPhase.failed,
      endedAt: now,
      endDetail: describeCallEnd(code, reason),
    );
  }
  return current.copyWith(
    phase: CallPhase.ended,
    endedAt: now,
    endDetail: describeCallEnd(code, reason),
  );
}
