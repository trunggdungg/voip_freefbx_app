/// Giai đoạn của kết nối SIP (WebSocket + đăng ký extension).
enum SipPhase {
  /// Chưa chạy (chưa đăng nhập hoặc đã đăng xuất).
  stopped,

  /// Đang mở kết nối WebSocket tới FreePBX.
  connecting,

  /// WebSocket đã mở, đang chờ FreePBX xác nhận đăng ký.
  registering,

  /// Đã đăng ký: có thể gọi và nhận cuộc gọi.
  registered,

  /// Mất WebSocket; thư viện đang tự kết nối lại.
  disconnected,

  /// FreePBX từ chối đăng ký hoặc không thể kết nối: cần người dùng xem lỗi.
  failed,

  /// Đã hủy đăng ký.
  unregistered,
}

class SipStatus {
  const SipStatus(this.phase, [this.detail]);

  const SipStatus.stopped() : this(SipPhase.stopped);
  const SipStatus.connecting() : this(SipPhase.connecting);
  const SipStatus.registering() : this(SipPhase.registering);
  const SipStatus.registered() : this(SipPhase.registered);
  const SipStatus.unregistered() : this(SipPhase.unregistered);
  const SipStatus.disconnected([String? detail])
    : this(SipPhase.disconnected, detail);
  const SipStatus.failed(String detail) : this(SipPhase.failed, detail);

  final SipPhase phase;

  /// Mô tả lỗi bằng tiếng Việt (nếu có).
  final String? detail;

  bool get isRegistered => phase == SipPhase.registered;

  /// Trạng thái cần người dùng can thiệp hoặc bấm "Kết nối lại".
  bool get canRetry =>
      phase == SipPhase.failed ||
      phase == SipPhase.disconnected ||
      phase == SipPhase.unregistered;

  @override
  bool operator ==(Object other) =>
      other is SipStatus && other.phase == phase && other.detail == detail;

  @override
  int get hashCode => Object.hash(phase, detail);

  @override
  String toString() => 'SipStatus($phase${detail == null ? '' : ', $detail'})';
}
