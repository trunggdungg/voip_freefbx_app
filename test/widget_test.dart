import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:voip_freefbx_app/app.dart';
import 'package:voip_freefbx_app/core/config/app_config.dart';
import 'package:voip_freefbx_app/core/config/app_config_provider.dart';
import 'package:voip_freefbx_app/core/permissions/permission_service.dart';

void main() {
  testWidgets('Màn hình M0 hiện môi trường và trạng thái quyền', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(
            env: AppEnv.dev,
            defaultOdooUrl: 'http://192.168.1.10:8069',
            defaultDatabase: 'odoo',
            allowBadCertificate: true,
          )),
          permissionStatusesProvider.overrideWith(
            (ref) async => {
              AppPermission.microphone: PermissionStatus.granted,
              AppPermission.notifications: PermissionStatus.denied,
            },
          ),
        ],
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EAUT VoIP'), findsOneWidget);
    expect(find.text('Môi trường: dev'), findsOneWidget);
    expect(find.text('http://192.168.1.10:8069'), findsOneWidget);
    expect(find.text('Micro'), findsOneWidget);
    // Micro đã cấp thì không có nút; Thông báo chưa cấp thì có nút "Cấp quyền".
    expect(find.text('Cấp quyền'), findsOneWidget);
  });

  test('AppConfig mặc định là dev và không bật chứng chỉ lỏng', () {
    final config = AppConfig.fromEnvironment();
    expect(config.env, AppEnv.dev);
    expect(config.allowBadCertificate, isFalse);
  });
}
