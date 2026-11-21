import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sip_ua/sip_ua.dart';
// ErrorCause không được sip_ua export; chỉ dùng trong test để dựng nguyên nhân kết thúc.
// ignore: implementation_imports
import 'package:sip_ua/src/event_manager/events.dart' show ErrorCause;
import 'package:voip_freefbx_app/app.dart';
import 'package:voip_freefbx_app/core/config/app_config.dart';
import 'package:voip_freefbx_app/core/config/app_config_provider.dart';
import 'package:voip_freefbx_app/core/permissions/permission_service.dart';
import 'package:voip_freefbx_app/features/auth/data/odoo_auth_repository.dart';
import 'package:voip_freefbx_app/features/auth/domain/auth_session.dart';
import 'package:voip_freefbx_app/features/call/data/call_state_mapper.dart';
import 'package:voip_freefbx_app/features/call/data/ringtone.dart';
import 'package:voip_freefbx_app/features/call/domain/call_session.dart';
import 'package:voip_freefbx_app/features/sip/data/sip_ua_client.dart';
import 'package:voip_freefbx_app/features/sip/data/voip_config_repository.dart';
import 'package:voip_freefbx_app/features/sip/domain/sip_status.dart';

import 'support/fakes.dart';

final _t0 = DateTime(2026, 1, 1, 9);

CallSession _outgoing() => const CallSession(
  id: 'c1',
  remoteNumber: '0912345678',
  direction: CallDirection.outgoing,
);

CallState _ev(CallStateEnum s, {Originator? originator, bool? audio}) =>
    CallState(s, originator: originator, audio: audio);

void main() {
  group('normalizeDialNumber', () {
    test('bỏ khoảng trắng, dấu chấm, gạch, ngoặc', () {
      expect(normalizeDialNumber('0912 345.678'), '0912345678');
      expect(normalizeDialNumber('(0912)-345-678'), '0912345678');
    });
    test('giữ + * #, bỏ chữ cái', () {
      expect(normalizeDialNumber('+84 912 345 678'), '+84912345678');
      expect(normalizeDialNumber('*43'), '*43');
      expect(normalizeDialNumber('abc'), '');
    });
  });

  group('applyCallState', () {
    test('gọi → đổ chuông → nghe máy (chỉ ghi giờ nghe máy một lần)', () {
      var s = applyCallState(
        _outgoing(),
        _ev(CallStateEnum.PROGRESS),
        now: _t0,
      );
      expect(s.phase, CallPhase.ringing);

      s = applyCallState(s, _ev(CallStateEnum.ACCEPTED), now: _t0);
      expect(s.phase, CallPhase.active);
      expect(s.answeredAt, _t0);

      final later = _t0.add(const Duration(seconds: 5));
      s = applyCallState(s, _ev(CallStateEnum.CONFIRMED), now: later);
      expect(
        s.answeredAt,
        _t0,
        reason: 'CONFIRMED không được đặt lại giờ nghe máy',
      );
      expect(s.durationAt(later), const Duration(seconds: 5));
    });

    test(
      'đang đàm thoại mà nhận PROGRESS muộn thì không quay về đổ chuông',
      () {
        var s = applyCallState(
          _outgoing(),
          _ev(CallStateEnum.ACCEPTED),
          now: _t0,
        );
        s = applyCallState(s, _ev(CallStateEnum.PROGRESS), now: _t0);
        expect(s.phase, CallPhase.active);
      },
    );

    test('tắt tiếng và giữ máy (chỉ tính giữ máy do mình)', () {
      var s = applyCallState(
        _outgoing(),
        _ev(CallStateEnum.ACCEPTED),
        now: _t0,
      );
      s = applyCallState(s, _ev(CallStateEnum.MUTED, audio: true), now: _t0);
      expect(s.muted, isTrue);
      s = applyCallState(s, _ev(CallStateEnum.UNMUTED, audio: true), now: _t0);
      expect(s.muted, isFalse);

      s = applyCallState(
        s,
        _ev(CallStateEnum.HOLD, originator: Originator.remote),
        now: _t0,
      );
      expect(s.held, isFalse, reason: 'bên kia giữ máy không phải mình giữ');
      s = applyCallState(
        s,
        _ev(CallStateEnum.HOLD, originator: Originator.local),
        now: _t0,
      );
      expect(s.held, isTrue);
      s = applyCallState(
        s,
        _ev(CallStateEnum.UNHOLD, originator: Originator.local),
        now: _t0,
      );
      expect(s.held, isFalse);
    });

    test('kết thúc: ghi giờ kết thúc, bỏ qua sự kiện đến muộn', () {
      var s = applyCallState(
        _outgoing(),
        _ev(CallStateEnum.ACCEPTED),
        now: _t0,
      );
      final end = _t0.add(const Duration(seconds: 12));
      s = applyCallState(s, _ev(CallStateEnum.ENDED), now: end);
      expect(s.phase, CallPhase.ended);
      expect(s.durationAt(DateTime(2030)), const Duration(seconds: 12));

      final after = applyCallState(
        s,
        _ev(CallStateEnum.MUTED, audio: true),
        now: end,
      );
      expect(identical(after, s), isTrue);
    });

    test('máy bận → thất bại, kèm lý do tiếng Việt', () {
      final s = applyCallState(
        _outgoing(),
        CallState(CallStateEnum.FAILED, cause: _cause(486, 'Busy Here')),
        now: _t0,
      );
      expect(s.phase, CallPhase.failed);
      expect(s.endDetail, 'Máy bận');
    });

    test('mình hủy khi đang đổ chuông (487) không phải là thất bại', () {
      final s = applyCallState(
        _outgoing(),
        CallState(CallStateEnum.FAILED, cause: _cause(487, 'Canceled')),
        now: _t0,
      );
      expect(s.phase, CallPhase.ended);
      expect(s.endDetail, 'Đã hủy cuộc gọi');
    });
  });

  group('cuộc gọi đến', () {
    const incoming = CallSession(
      id: 'in1',
      remoteNumber: '1096',
      remoteName: 'Tư vấn viên B',
      direction: CallDirection.incoming,
      phase: CallPhase.ringing,
    );

    test('đang đổ chuông thì chờ mình trả lời', () {
      expect(incoming.isIncomingRinging, isTrue);
      // PROGRESS không được đổi trạng thái của cuộc gọi đến.
      final s = applyCallState(incoming, _ev(CallStateEnum.PROGRESS), now: _t0);
      expect(s.isIncomingRinging, isTrue);
    });

    test(
      'trả lời → đang đàm thoại, rồi kết thúc bình thường (không phải nhỡ)',
      () {
        var s = applyCallState(incoming, _ev(CallStateEnum.ACCEPTED), now: _t0);
        expect(s.phase, CallPhase.active);
        s = applyCallState(
          s,
          CallState(CallStateEnum.ENDED, originator: Originator.remote),
          now: _t0.add(const Duration(seconds: 30)),
        );
        expect(s.phase, CallPhase.ended);
        expect(s.missed, isFalse);
      },
    );

    test('bên gọi gác máy khi mình chưa nghe → cuộc gọi nhỡ', () {
      final s = applyCallState(
        incoming,
        CallState(
          CallStateEnum.FAILED,
          originator: Originator.remote,
          cause: _cause(487, 'Canceled'),
        ),
        now: _t0,
      );
      expect(s.phase, CallPhase.ended);
      expect(s.missed, isTrue);
      expect(s.endDetail, 'Cuộc gọi nhỡ');
    });

    test('mình từ chối → không tính là nhỡ', () {
      final s = applyCallState(
        incoming,
        CallState(
          CallStateEnum.FAILED,
          originator: Originator.local,
          cause: _cause(486, 'Busy Here'),
        ),
        now: _t0,
      );
      expect(s.missed, isFalse);
      expect(s.endDetail, 'Đã từ chối cuộc gọi');
    });

    test('người khác trong nhóm đã nghe máy → không tính là nhỡ', () {
      final s = applyCallState(
        incoming,
        CallState(
          CallStateEnum.FAILED,
          originator: Originator.remote,
          cause: _cause(487, 'Call completed elsewhere'),
        ),
        now: _t0,
      );
      expect(s.missed, isFalse);
      expect(s.endDetail, 'Đã được máy khác trả lời');
    });
  });

  test('describeCallEnd: các mã thường gặp', () {
    expect(describeCallEnd(404, null), 'Số không tồn tại');
    expect(describeCallEnd(603, null), contains('từ chối'));
    expect(describeCallEnd(488, null), contains('âm thanh'));
    expect(describeCallEnd(403, null), contains('outbound route'));
    expect(
      describeCallEnd(null, 'User Denied Media Access'),
      contains('quyền micro'),
    );
    expect(describeCallEnd(null, null), 'Cuộc gọi kết thúc');
    expect(describeCallEnd(500, 'Server Error'), contains('mã 500'));
  });

  group('luồng gọi đi trên giao diện', () {
    const session = AuthSession(
      baseUrl: 'http://10.0.2.2:8069',
      database: 'eaut',
      login: 'tv1',
      displayName: 'A',
    );

    Widget app(
      FakeSipClient sip, {
      FakePermissionService? perms,
      FakeRingtone? ringtone,
    }) => ProviderScope(
      overrides: [
        ringtoneProvider.overrideWithValue(ringtone ?? FakeRingtone()),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            env: AppEnv.dev,
            defaultOdooUrl: '',
            defaultDatabase: '',
            allowBadCertificate: false,
          ),
        ),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(restored: session),
        ),
        voipConfigRepositoryProvider.overrideWithValue(
          FakeVoipConfigRepository(config: sampleConfig()),
        ),
        sipClientProvider.overrideWithValue(sip),
        callServiceProvider.overrideWithValue(sip),
        permissionServiceProvider.overrideWithValue(
          perms ?? FakePermissionService(),
        ),
        permissionStatusesProvider.overrideWith(
          (ref) => (perms ?? FakePermissionService()).statuses(),
        ),
      ],
      child: const App(),
    );

    // Sự kiện đi qua Stream nên cần hai lần pump (một để nhận sự kiện, một để dựng lại).
    // Không dùng pumpAndSettle khi đang đàm thoại vì đồng hồ chạy mỗi giây.
    Future<void> flush(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    Future<void> openDialPad(WidgetTester tester) async {
      await tester.tap(find.text('Bàn phím'));
      await tester.pumpAndSettle();
    }

    Future<void> typeDigits(WidgetTester tester, String digits) async {
      for (final d in digits.split('')) {
        await tester.tap(find.byKey(ValueKey('key-$d')));
        await tester.pump();
      }
    }

    testWidgets(
      'bàn phím → đang gọi → đổ chuông → nghe máy → tắt tiếng → kết thúc',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final sip = FakeSipClient();
        await tester.pumpWidget(app(sip));
        await tester.pumpAndSettle();
        sip.push(const SipStatus.registered());
        await tester.pumpAndSettle();

        await openDialPad(tester);
        await typeDigits(tester, '0912');
        expect(find.byKey(const ValueKey('dial-number')), findsOneWidget);
        expect(find.text('0912'), findsOneWidget);

        await tester.tap(find.byTooltip('Gọi'));
        await tester.pumpAndSettle();

        expect(sip.dialed, ['0912']);
        expect(find.byKey(const ValueKey('call-status')), findsOneWidget);
        expect(find.text('Đang gọi…'), findsOneWidget);
        expect(find.text('0912'), findsOneWidget);

        sip.pushCall(sip.currentCall!.copyWith(phase: CallPhase.ringing));
        await tester.pumpAndSettle();
        expect(find.text('Đổ chuông…'), findsOneWidget);

        sip.pushCall(
          sip.currentCall!.copyWith(
            phase: CallPhase.active,
            answeredAt: DateTime.now(),
          ),
        );
        await flush(tester);
        final status = tester.widget<Text>(
          find.byKey(const ValueKey('call-status')),
        );
        expect(status.data, matches(RegExp(r'^\d{2}:\d{2}$')));

        await tester.tap(find.byTooltip('Tắt tiếng'));
        await flush(tester);
        expect(sip.currentCall!.muted, isTrue);

        await tester.tap(find.byTooltip('Kết thúc'));
        await flush(tester);
        expect(sip.hangups, 1);
        expect(find.textContaining('Cuộc gọi kết thúc'), findsOneWidget);

        // Sau vài giây màn hình cuộc gọi tự đóng, quay lại bàn phím.
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('call-status')), findsNothing);
        expect(find.byKey(const ValueKey('dial-number')), findsOneWidget);
      },
    );

    testWidgets('máy bận: hiện lý do bằng chữ đỏ rồi tự đóng', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final sip = FakeSipClient();
      await tester.pumpWidget(app(sip));
      await tester.pumpAndSettle();
      sip.push(const SipStatus.registered());
      await tester.pumpAndSettle();

      await openDialPad(tester);
      await typeDigits(tester, '1096');
      await tester.tap(find.byTooltip('Gọi'));
      await tester.pumpAndSettle();

      sip.pushCall(
        sip.currentCall!.copyWith(
          phase: CallPhase.failed,
          endedAt: DateTime.now(),
          endDetail: 'Máy bận',
        ),
      );
      await flush(tester);
      expect(find.text('Máy bận'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Máy bận'), findsNothing);
    });

    testWidgets('chưa đăng ký: nút Gọi bị khóa và có cảnh báo', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final sip = FakeSipClient();
      await tester.pumpWidget(app(sip));
      await tester.pumpAndSettle();
      // Fake đang ở trạng thái "đang kết nối": chưa đăng ký.

      await openDialPad(tester);
      await typeDigits(tester, '0912');
      expect(find.textContaining('Chưa đăng ký với tổng đài'), findsOneWidget);

      await tester.tap(find.byTooltip('Gọi'), warnIfMissed: false);
      await tester.pump();
      expect(sip.dialed, isEmpty);
    });

    testWidgets('không có quyền micro: báo lỗi, không gọi', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final sip = FakeSipClient();
      await tester.pumpWidget(
        app(sip, perms: FakePermissionService(micGranted: false)),
      );
      await tester.pumpAndSettle();
      sip.push(const SipStatus.registered());
      await tester.pumpAndSettle();

      await openDialPad(tester);
      await typeDigits(tester, '0912');
      await tester.tap(find.byTooltip('Gọi'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Cần cấp quyền micro'), findsOneWidget);
      expect(sip.dialed, isEmpty);
    });

    const incomingCall = CallSession(
      id: 'in1',
      remoteNumber: '1096',
      remoteName: 'Tư vấn viên B',
      direction: CallDirection.incoming,
      phase: CallPhase.ringing,
    );

    Future<FakeSipClient> pumpRegistered(
      WidgetTester tester, {
      FakePermissionService? perms,
      FakeRingtone? ringtone,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sip = FakeSipClient();
      await tester.pumpWidget(app(sip, perms: perms, ringtone: ringtone));
      await tester.pumpAndSettle();
      sip.push(const SipStatus.registered());
      await tester.pumpAndSettle();
      return sip;
    }

    testWidgets(
      'có cuộc gọi đến: hiện màn hình, đổ chuông, trả lời, kết thúc',
      (tester) async {
        final ringtone = FakeRingtone();
        final sip = await pumpRegistered(tester, ringtone: ringtone);

        sip.pushCall(incomingCall);
        await tester.pumpAndSettle();

        expect(find.text('Tư vấn viên B'), findsOneWidget);
        expect(find.text('1096'), findsOneWidget);
        expect(find.text('Cuộc gọi đến…'), findsOneWidget);
        expect(find.byTooltip('Trả lời'), findsOneWidget);
        expect(find.byTooltip('Từ chối'), findsOneWidget);
        expect(find.byTooltip('Tắt tiếng'), findsNothing);
        expect(ringtone.ringing, isTrue);

        await tester.tap(find.byTooltip('Trả lời'));
        await flush(tester);
        expect(sip.answers, 1);
        expect(
          ringtone.ringing,
          isFalse,
          reason: 'trả lời xong phải tắt chuông',
        );
        expect(find.byTooltip('Tắt tiếng'), findsOneWidget);
        expect(find.byTooltip('Trả lời'), findsNothing);

        await tester.tap(find.byTooltip('Kết thúc'));
        await flush(tester);
        expect(sip.hangups, 1);

        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('call-status')), findsNothing);
      },
    );

    testWidgets('từ chối cuộc gọi đến: tắt chuông, hiện kết quả rồi đóng', (
      tester,
    ) async {
      final ringtone = FakeRingtone();
      final sip = await pumpRegistered(tester, ringtone: ringtone);

      sip.pushCall(incomingCall);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Từ chối'));
      await tester.pumpAndSettle();

      expect(sip.rejects, 1);
      expect(sip.answers, 0);
      expect(ringtone.ringing, isFalse);
      expect(find.text('Đã từ chối cuộc gọi'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Đã từ chối cuộc gọi'), findsNothing);
    });

    testWidgets(
      'bên gọi gác máy trước khi nghe: tắt chuông, báo cuộc gọi nhỡ',
      (tester) async {
        final ringtone = FakeRingtone();
        final sip = await pumpRegistered(tester, ringtone: ringtone);

        sip.pushCall(incomingCall);
        await tester.pumpAndSettle();
        expect(ringtone.ringing, isTrue);

        sip.pushCall(
          incomingCall.copyWith(
            phase: CallPhase.ended,
            endedAt: DateTime.now(),
            endDetail: 'Cuộc gọi nhỡ',
            missed: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(ringtone.ringing, isFalse);
        expect(find.text('Cuộc gọi nhỡ'), findsOneWidget);
        expect(find.byTooltip('Trả lời'), findsNothing);
      },
    );

    testWidgets(
      'trả lời khi chưa có quyền micro: từ chối cuộc gọi và báo lỗi',
      (tester) async {
        final sip = await pumpRegistered(
          tester,
          perms: FakePermissionService(micGranted: false),
        );

        sip.pushCall(incomingCall);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Trả lời'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Cần cấp quyền micro để nghe máy'),
          findsOneWidget,
        );
        expect(sip.answers, 0);
        expect(sip.rejects, 1);
      },
    );
  });
}

ErrorCause _cause(int code, String reason) =>
    ErrorCause(status_code: code, reason_phrase: reason);
