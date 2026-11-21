import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Các quyền Android mà app gọi điện cần.
enum AppPermission {
  microphone('Micro', 'Để nói chuyện trong cuộc gọi', Permission.microphone),
  notifications(
    'Thông báo',
    'Để hiện cuộc gọi đến và cuộc gọi nhỡ',
    Permission.notification,
  );

  const AppPermission(this.label, this.reason, this.permission);

  final String label;
  final String reason;
  final Permission permission;
}

/// Bọc `permission_handler` để UI và test không phụ thuộc trực tiếp vào plugin.
class PermissionService {
  const PermissionService();

  Future<Map<AppPermission, PermissionStatus>> statuses() async {
    return {for (final p in AppPermission.values) p: await p.permission.status};
  }

  /// Xin quyền. Nếu người dùng đã chọn "không hỏi lại" thì mở màn hình cài đặt app.
  Future<PermissionStatus> request(AppPermission p) async {
    final current = await p.permission.status;
    if (current.isPermanentlyDenied) {
      await openAppSettings();
      return current;
    }
    return p.permission.request();
  }
}

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => const PermissionService(),
);

final permissionStatusesProvider =
    FutureProvider.autoDispose<Map<AppPermission, PermissionStatus>>(
      (ref) => ref.watch(permissionServiceProvider).statuses(),
    );
