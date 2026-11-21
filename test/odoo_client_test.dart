import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voip_freefbx_app/core/network/api_exceptions.dart';
import 'package:voip_freefbx_app/core/network/odoo_client.dart';
import 'package:voip_freefbx_app/core/storage/key_value_store.dart';
import 'package:voip_freefbx_app/features/auth/data/odoo_auth_repository.dart';
import 'package:voip_freefbx_app/features/sip/data/voip_config_repository.dart';

import 'support/fakes.dart';

/// Adapter giả: trả lời theo đường dẫn, ghi lại request để kiểm tra.
class FakeAdapter implements HttpClientAdapter {
  final Map<String, ResponseBody Function(RequestOptions)> routes = {};
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = Uri.parse(options.path).path;
    final handler = routes[path];
    if (handler == null) return ResponseBody.fromString('not found', 404);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object body, {Map<String, List<String>>? headers}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        ...?headers,
      },
    );

void main() {
  late FakeAdapter adapter;
  late OdooClient client;
  late MemoryStore store;

  setUp(() {
    adapter = FakeAdapter();
    client = OdooClient(Dio()..httpClientAdapter = adapter);
    store = MemoryStore();
  });

  group('normalizeBaseUrl', () {
    test('thêm http, bỏ dấu / cuối', () {
      expect(
        normalizeBaseUrl(' 10.0.2.2:8069/ ', requireHttps: false),
        'http://10.0.2.2:8069',
      );
      expect(
        normalizeBaseUrl('https://odoo.eaut.edu.vn//', requireHttps: true),
        'https://odoo.eaut.edu.vn',
      );
    });
    test('prod bắt buộc https, từ chối giá trị rác', () {
      expect(normalizeBaseUrl('http://odoo.local', requireHttps: true), isNull);
      expect(normalizeBaseUrl('', requireHttps: false), isNull);
      expect(normalizeBaseUrl('ftp://x.com', requireHttps: false), isNull);
    });
  });

  group('đăng nhập', () {
    test('thành công: lưu session, không lưu mật khẩu', () async {
      adapter.routes['/web/session/authenticate'] = (o) {
        final params = (o.data as Map)['params'] as Map;
        expect(params['db'], 'eaut');
        expect(params['login'], 'tv1');
        return jsonBody(
          {
            'jsonrpc': '2.0',
            'id': 1,
            'result': {'uid': 7, 'name': 'Tư vấn viên A'},
          },
          headers: {
            'set-cookie': ['session_id=abc123; Path=/; HttpOnly'],
          },
        );
      };
      final repo = OdooAuthRepository(client, store);

      final session = await repo.login(
        baseUrl: 'http://10.0.2.2:8069',
        database: 'eaut',
        login: 'tv1',
        password: 'mat-khau-bi-mat',
      );

      expect(session.displayName, 'Tư vấn viên A');
      expect(store.data[StoreKeys.sessionId], 'abc123');
      expect(
        store.data.values.any((v) => v.contains('mat-khau-bi-mat')),
        isFalse,
      );
    });

    test('sai mật khẩu (Odoo trả lỗi AccessDenied)', () async {
      adapter.routes['/web/session/authenticate'] = (_) => jsonBody({
        'jsonrpc': '2.0',
        'id': 1,
        'error': {
          'code': 200,
          'message': 'Odoo Server Error',
          'data': {
            'name': 'odoo.exceptions.AccessDenied',
            'message': 'Access Denied',
          },
        },
      });
      final repo = OdooAuthRepository(client, store);

      expect(
        () => repo.login(
          baseUrl: 'http://x',
          database: 'd',
          login: 'a',
          password: 'b',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('result không có uid vẫn coi là sai mật khẩu', () async {
      adapter.routes['/web/session/authenticate'] = (_) => jsonBody({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'uid': false},
      });
      final repo = OdooAuthRepository(client, store);
      expect(
        () => repo.login(
          baseUrl: 'http://x',
          database: 'd',
          login: 'a',
          password: 'b',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('khôi phục phiên đã lưu và gửi cookie khi gọi API', () async {
      store.data.addAll({
        StoreKeys.odooUrl: 'http://10.0.2.2:8069',
        StoreKeys.odooDb: 'eaut',
        StoreKeys.odooLogin: 'tv1',
        StoreKeys.sessionId: 'saved-session',
      });
      adapter.routes['/voip/config'] = (_) => jsonBody({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'success': false, 'error': 'x'},
      });
      final session = await OdooAuthRepository(client, store).restore();
      expect(session?.login, 'tv1');

      await expectLater(
        OdooVoipConfigRepository(client).fetch(),
        throwsA(isA<VoipNotConfiguredException>()),
      );
      expect(
        adapter.requests.single.headers['Cookie'],
        'session_id=saved-session',
      );
    });

    test('không có phiên đã lưu thì trả về null', () async {
      expect(await OdooAuthRepository(client, store).restore(), isNull);
    });
  });

  group('/voip/config', () {
    setUp(() => client.configure(baseUrl: 'http://x', sessionId: 's'));

    test(
      'đọc đúng cấu hình từ phản hồi của module voip_webrtc_freepbx',
      () async {
        adapter.routes['/voip/config'] = (_) => jsonBody({
          'jsonrpc': '2.0',
          'id': 1,
          'result': {
            'success': true,
            'config': {
              'server': {
                'host': 'pbx.example.com',
                'websocket_url': 'wss://pbx.example.com:8089/ws',
                'port': 8089,
                'realm': 'pbx.example.com',
                'use_tls': true,
              },
              'user': {
                'username': '1096',
                'password': 'secret-sip',
                'display_name': 'Tư vấn viên A',
                'auto_answer': false,
              },
              'logging': {},
            },
          },
        });

        final c = await OdooVoipConfigRepository(client).fetch();
        expect(c.user.username, '1096');
        expect(c.server.websocketUrl, 'wss://pbx.example.com:8089/ws');
        expect(c.server.isLoopback, isFalse);
        expect(c.user.toString(), isNot(contains('secret-sip')));
      },
    );

    test('tài khoản chưa có voip.user', () async {
      adapter.routes['/voip/config'] = (_) => jsonBody({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {
          'error': 'Người dùng hiện tại chưa được cấu hình điện thoại VoIP',
        },
      });
      expect(
        OdooVoipConfigRepository(client).fetch(),
        throwsA(
          isA<VoipNotConfiguredException>().having(
            (e) => e.message,
            'message',
            contains('chưa được cấu hình'),
          ),
        ),
      );
    });

    test('websocket_url là localhost thì bị cảnh báo', () async {
      adapter.routes['/voip/config'] = (_) => jsonBody({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {
          'success': true,
          'config': {
            'server': {
              'host': 'localhost',
              'websocket_url': 'wss://localhost:8089/ws',
            },
            'user': {'username': '1096', 'password': 'p'},
          },
        },
      });
      final c = await OdooVoipConfigRepository(client).fetch();
      expect(c.server.isLoopback, isTrue);
    });

    test('phiên hết hạn', () async {
      adapter.routes['/voip/config'] = (_) => jsonBody({
        'jsonrpc': '2.0',
        'id': 1,
        'error': {
          'code': 100,
          'message': 'Odoo Session Expired',
          'data': {'name': 'odoo.http.SessionExpiredException'},
        },
      });
      expect(
        OdooVoipConfigRepository(client).fetch(),
        throwsA(isA<SessionExpiredException>()),
      );
    });

    test('địa chỉ sai (404) báo lỗi dễ hiểu', () async {
      expect(
        OdooVoipConfigRepository(client).fetch(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Không tìm thấy đường dẫn'),
          ),
        ),
      );
    });
  });
}
