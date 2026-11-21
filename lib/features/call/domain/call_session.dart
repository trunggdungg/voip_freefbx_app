enum CallDirection { outgoing, incoming }

enum CallPhase {
  /// Đang gửi yêu cầu gọi.
  dialing,

  /// Bên kia đang đổ chuông.
  ringing,

  /// Đã nghe máy, đang đàm thoại.
  active,

  /// Kết thúc bình thường (hoặc do người dùng hủy).
  ended,

  /// Không gọi được (máy bận, sai số, bị từ chối...).
  failed,
}

/// Một cuộc gọi đang diễn ra (hoặc vừa kết thúc, để hiện kết quả vài giây).
class CallSession {
  const CallSession({
    required this.id,
    required this.remoteNumber,
    required this.direction,
    this.remoteName,
    this.phase = CallPhase.dialing,
    this.muted = false,
    this.held = false,
    this.speakerOn = false,
    this.answeredAt,
    this.endedAt,
    this.endDetail,
    this.missed = false,
  });

  final String id;
  final String remoteNumber;
  final String? remoteName;
  final CallDirection direction;
  final CallPhase phase;
  final bool muted;
  final bool held;
  final bool speakerOn;

  /// Lúc nghe máy; dùng để tính thời lượng đàm thoại.
  final DateTime? answeredAt;
  final DateTime? endedAt;

  /// Lý do kết thúc/thất bại bằng tiếng Việt.
  final String? endDetail;

  /// Cuộc gọi đến mà mình chưa kịp nghe và bên gọi đã gác máy.
  final bool missed;

  bool get isTerminal => phase == CallPhase.ended || phase == CallPhase.failed;
  bool get isActive => phase == CallPhase.active;

  /// Cuộc gọi đến đang đổ chuông, chờ mình trả lời hoặc từ chối.
  bool get isIncomingRinging =>
      direction == CallDirection.incoming && phase == CallPhase.ringing;

  /// Thời lượng đàm thoại (chỉ tính từ lúc nghe máy).
  Duration? durationAt(DateTime now) {
    final start = answeredAt;
    if (start == null) return null;
    return (endedAt ?? now).difference(start);
  }

  CallSession copyWith({
    CallPhase? phase,
    bool? muted,
    bool? held,
    bool? speakerOn,
    DateTime? answeredAt,
    DateTime? endedAt,
    String? endDetail,
    bool? missed,
  }) => CallSession(
    id: id,
    remoteNumber: remoteNumber,
    remoteName: remoteName,
    direction: direction,
    phase: phase ?? this.phase,
    muted: muted ?? this.muted,
    held: held ?? this.held,
    speakerOn: speakerOn ?? this.speakerOn,
    answeredAt: answeredAt ?? this.answeredAt,
    endedAt: endedAt ?? this.endedAt,
    endDetail: endDetail ?? this.endDetail,
    missed: missed ?? this.missed,
  );
}

/// Lỗi khi bắt đầu cuộc gọi; `message` là tiếng Việt, hiển thị thẳng cho người dùng.
class CallException implements Exception {
  const CallException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Chuẩn hóa số bấm trên bàn phím: bỏ khoảng trắng, dấu chấm, gạch, ngoặc.
/// Giữ chữ số, `*`, `#` và `+` (mã tính năng như `*43` vẫn gọi được).
/// Trả về chuỗi rỗng nếu không còn ký tự hợp lệ.
String normalizeDialNumber(String input) =>
    input.replaceAll(RegExp(r'[^0-9*#+]'), '');
