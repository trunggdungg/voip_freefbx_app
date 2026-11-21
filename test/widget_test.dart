import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:voip_freefbx_app/app.dart';
import 'package:voip_freefbx_app/core/config/app_config.dart';
import 'package:voip_freefbx_app/core/config/app_config_provider.dart';
import 'package:voip_freefbx_app/core/network/api_exceptions.dart';
import 'package:voip_freefbx_app/core/permissions/permission_service.dart';
import 'package:voip_freefbx_app/features/auth/data/odoo_auth_repository.dart';
import 'package:voip_freefbx_app/features/auth/domain/auth_session.dart';
import 'package:voip_freefbx_app/features/sip/data/sip_ua_client.dart';
import 'package:voip_freefbx_app/features/sip/data/voip_config_repository.dart';
import 'package:voip_freefbx_app/features/sip/domain/sip_status.dart';

import 'support/fakes.dart';

const _devConfig = AppConfig(
  env: AppEnv.dev,
  defaultOdooUrl: 'http://10.0.2.2:8069',
  defaultDatabase: 'eaut',
  allowBadCertificate: true,
);

Widget _app({
  required FakeAuthRepository auth,
  required FakeVoipConfigRepository voip,
  FakeSipClient? sip,
}) {
  return ProviderScope(
    overrides: [
      sipClientProvider.overrideWithValue(sip ?? FakeSipClient()),
      appConfigProvider.overrideWithValue(_devConfig),
      authRepositoryProvider.overrideWithValue(auth),
      voipConfigRepositoryProvider.overrideWithValue(voip),
      permissionStatusesProvider.overrideWith(
        (ref) async => {
          AppPermission.microphone: PermissionStatus.granted,
          AppPermission.notifications: PermissionStatus.denied,
        },
      ),
    ],
    child: const App(),
  );
}

void main() {
  testWidgets('chưa đăng nhập: hiện form, gợi ý sẵn URL/database từ cấu hình', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        auth: FakeAuthRepository(),
        voip: FakeVoipConfigRepository(config: sampleConfig()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Đăng nhập bằng tài khoản Odoo'), findsOneWidget);
    expect(find.text('http://10.0.2.2:8069'), findsOneWidget);
    expect(find.text('eaut'), findsOneWidget);
  });

  testWidgets('bỏ trống thì báo lỗi, không gọi đăng nhập', (tester) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(
      _app(
        auth: auth,
        voip: FakeVoipConfigRepository(config: sampleConfig()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();

    expect(find.text('Nhập tên đăng nhập'), findsOneWidget);
    expect(find.text('Nhập mật khẩu'), findsOneWidget);
    expect(auth.lastPassword, isNull);
  });

  testWidgets('sai mật khẩu hiện thông báo lỗi và ở lại màn đăng nhập', (
    tester,
  ) async {
    final auth = FakeAuthRepository(
      failWith: const AuthException('Sai tên đăng nhập hoặc mật khẩu.'),
    );
    await tester.pumpWidget(
      _app(
        auth: auth,
        voip: FakeVoipConfigRepository(config: sampleConfig()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tên đăng nhập'),
      'tv1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mật khẩu'),
      'sai',
    );
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();

    expect(find.text('Sai tên đăng nhập hoặc mật khẩu.'), findsOneWidget);
    expect(find.text('Đăng nhập bằng tài khoản Odoo'), findsOneWidget);
  });

  testWidgets(
    'đăng nhập đúng: sang trang chính, hiện cấu hình SIP, ẩn mật khẩu SIP',
    (tester) async {
      // Màn hình đủ cao để ListView dựng hết các thẻ.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          auth: FakeAuthRepository(),
          voip: FakeVoipConfigRepository(config: sampleConfig()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên đăng nhập'),
        'tv1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mật khẩu'),
        'ok',
      );
      await tester.tap(find.text('Đăng nhập'));
      await tester.pumpAndSettle();

      expect(find.text('Cấu hình điện thoại (SIP)'), findsOneWidget);
      expect(find.text('1096'), findsOneWidget);
      expect(find.text('wss://pbx.example.com:8089/ws'), findsOneWidget);
      expect(find.text('••••••••'), findsOneWidget);
      expect(find.textContaining('secret-sip'), findsNothing);
      expect(find.text('Cấp quyền'), findsOneWidget);
    },
  );

  testWidgets('đã có phiên lưu sẵn: vào thẳng trang chính; đăng xuất về form', (
    tester,
  ) async {
    final auth = FakeAuthRepository(
      restored: const AuthSession(
        baseUrl: 'http://10.0.2.2:8069',
        database: 'eaut',
        login: 'tv1',
        displayName: 'Tư vấn viên A',
      ),
    );
    await tester.pumpWidget(
      _app(
        auth: auth,
        voip: FakeVoipConfigRepository(config: sampleConfig()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cấu hình điện thoại (SIP)'), findsOneWidget);

    await tester.tap(find.byTooltip('Đăng xuất'));
    await tester.pumpAndSettle();

    expect(auth.loggedOut, isTrue);
    expect(find.text('Đăng nhập bằng tài khoản Odoo'), findsOneWidget);
  });

  testWidgets('tài khoản chưa có voip.user: hiện lỗi và nút Thử lại', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        auth: FakeAuthRepository(
          restored: const AuthSession(
            baseUrl: 'http://10.0.2.2:8069',
            database: 'eaut',
            login: 'tv1',
            displayName: 'Tư vấn viên A',
          ),
        ),
        voip: FakeVoipConfigRepository(
          error: const VoipNotConfiguredException(
            'Người dùng hiện tại chưa được cấu hình điện thoại VoIP',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('chưa được cấu hình điện thoại VoIP'),
      findsOneWidget,
    );
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('websocket_url là localhost thì có cảnh báo', (tester) async {
    await tester.pumpWidget(
      _app(
        auth: FakeAuthRepository(
          restored: const AuthSession(
            baseUrl: 'http://10.0.2.2:8069',
            database: 'eaut',
            login: 'tv1',
            displayName: 'A',
          ),
        ),
        voip: FakeVoipConfigRepository(
          config: sampleConfig(wss: 'wss://localhost:8089/ws'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('điện thoại không kết nối được'),
      findsOneWidget,
    );
  });

  testWidgets('hiện trạng thái đăng ký SIP và nút Kết nối lại khi lỗi', (
    tester,
  ) async {
    final sip = FakeSipClient();
    await tester.pumpWidget(
      _app(
        auth: FakeAuthRepository(
          restored: const AuthSession(
            baseUrl: 'http://10.0.2.2:8069',
            database: 'eaut',
            login: 'tv1',
            displayName: 'A',
          ),
        ),
        voip: FakeVoipConfigRepository(config: sampleConfig()),
        sip: sip,
      ),
    );
    await tester.pumpAndSettle();

    // Có cấu hình thì tự kết nối đúng extension của người dùng.
    expect(sip.startedUsers, ['1096']);
    expect(find.text('Đang kết nối tổng đài…'), findsOneWidget);

    sip.push(const SipStatus.registered());
    await tester.pumpAndSettle();
    expect(find.text('Đã đăng ký, sẵn sàng gọi'), findsOneWidget);
    expect(find.text('Kết nối lại'), findsNothing);

    sip.push(const SipStatus.failed('FreePBX từ chối đăng ký (mã 403)'));
    await tester.pumpAndSettle();
    expect(find.text('Không đăng ký được'), findsOneWidget);
    expect(find.textContaining('mã 403'), findsOneWidget);

    await tester.tap(find.text('Kết nối lại'));
    await tester.pumpAndSettle();
    expect(sip.startedUsers, ['1096', '1096']);
  });

  testWidgets('đăng xuất thì hủy đăng ký SIP', (tester) async {
    final sip = FakeSipClient();
    await tester.pumpWidget(
      _app(
        auth: FakeAuthRepository(
          restored: const AuthSession(
            baseUrl: 'http://10.0.2.2:8069',
            database: 'eaut',
            login: 'tv1',
            displayName: 'A',
          ),
        ),
        voip: FakeVoipConfigRepository(config: sampleConfig()),
        sip: sip,
      ),
    );
    await tester.pumpAndSettle();
    expect(sip.stopCount, 0);

    await tester.tap(find.byTooltip('Đăng xuất'));
    await tester.pumpAndSettle();

    expect(sip.stopCount, greaterThanOrEqualTo(1));
    expect(find.text('Đăng nhập bằng tài khoản Odoo'), findsOneWidget);
  });
}
