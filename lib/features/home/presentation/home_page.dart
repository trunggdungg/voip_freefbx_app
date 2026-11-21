import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/permissions/permission_service.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../sip/domain/voip_config.dart';
import '../../sip/presentation/voip_config_provider.dart';

/// Màn hình chính tạm thời của M1: hiện tài khoản, cấu hình SIP lấy từ Odoo và quyền.
/// M2 sẽ thêm trạng thái đăng ký SIP, M3 thêm bàn phím gọi.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).value;
    final config = ref.watch(voipConfigProvider);
    final statuses = ref.watch(permissionStatusesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('EAUT VoIP'),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle),
              title: Text(session?.displayName ?? ''),
              subtitle: Text('${session?.login ?? ''}\n${session?.baseUrl ?? ''}'),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 16),
          Text('Cấu hình điện thoại (SIP)', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          config.when(
            data: (c) => _ConfigCard(config: c),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$e',
                        style: TextStyle(
                            color: theme.colorScheme.onErrorContainer)),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(voipConfigProvider),
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Quyền của ứng dụng', style: theme.textTheme.titleMedium),
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

class _ConfigCard extends StatelessWidget {
  const _ConfigCard({required this.config});

  final VoipConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final server = config.server;
    final user = config.user;

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(label, style: theme.textTheme.bodySmall),
              ),
              Expanded(child: Text(value)),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row('Extension', user.username),
            row('Tên hiển thị', user.displayName),
            row('Mật khẩu SIP', '••••••••'),
            row('Máy chủ', server.host.isEmpty ? '(chưa có)' : server.host),
            row('WebSocket', server.websocketUrl ?? '(chưa cấu hình)'),
            if (server.realm != null) row('Realm', server.realm!),
            row('Tự trả lời', user.autoAnswer ? 'Bật' : 'Tắt'),
            if (server.websocketUrl == null) ...[
              const SizedBox(height: 8),
              Text(
                'Máy chủ VoIP trong Odoo chưa có địa chỉ WebSocket (wss://…).',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ] else if (server.isLoopback) ...[
              const SizedBox(height: 8),
              Text(
                'Địa chỉ WebSocket đang là localhost/127.0.0.1 nên điện thoại '
                'không kết nối được. Sửa trong Odoo (VoIP > Máy chủ) thành IP '
                'hoặc tên miền của FreePBX.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
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
