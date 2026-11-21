import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/config/app_config_provider.dart';
import '../../../core/permissions/permission_service.dart';

/// Màn hình tạm của M0: xác nhận app chạy đúng môi trường và kiểm tra quyền.
/// Sẽ được thay bằng màn đăng nhập ở M1.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final statuses = ref.watch(permissionStatusesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('EAUT VoIP')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_ethernet),
              title: Text('Môi trường: ${config.env.name}'),
              subtitle: Text(
                config.defaultOdooUrl.isEmpty
                    ? 'Chưa cấu hình ODOO_URL'
                    : config.defaultOdooUrl,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Quyền của ứng dụng',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          statuses.when(
            data: (map) => Column(
              children: [
                for (final entry in map.entries)
                  _PermissionTile(permission: entry.key, status: entry.value),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Không đọc được quyền: $e'),
          ),
        ],
      ),
    );
  }
}

class _PermissionTile extends ConsumerWidget {
  const _PermissionTile({required this.permission, required this.status});

  final AppPermission permission;
  final PermissionStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final granted = status.isGranted;
    return Card(
      child: ListTile(
        leading: Icon(
          granted ? Icons.check_circle : Icons.error_outline,
          color: granted ? Colors.green : Theme.of(context).colorScheme.error,
        ),
        title: Text(permission.label),
        subtitle: Text(permission.reason),
        trailing: granted
            ? null
            : FilledButton(
                onPressed: () async {
                  await ref.read(permissionServiceProvider).request(permission);
                  ref.invalidate(permissionStatusesProvider);
                },
                child: Text(
                  status.isPermanentlyDenied ? 'Mở cài đặt' : 'Cấp quyền',
                ),
              ),
      ),
    );
  }
}
