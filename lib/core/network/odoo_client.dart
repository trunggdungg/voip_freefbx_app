import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../config/app_config_provider.dart';
import 'api_exceptions.dart';

/// Chuẩn hóa địa chỉ Odoo người dùng nhập. Trả về null nếu không hợp lệ.
///
/// - tự thêm `http://` nếu thiếu, bỏ dấu `/` cuối;
/// - môi trường prod bắt buộc `https`.
String? normalizeBaseUrl(String input, {required bool requireHttps}) {
  var url = input.trim();
  if (url.isEmpty) return null;
  if (!url.contains('://')) url = 'http://$url';
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (requireHttps && uri.scheme != 'https') return null;
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// Client gọi JSON-RPC của Odoo bằng cookie `session_id`.
///
/// Giai đoạn đầu app dùng các endpoint sẵn có của Odoo (`/web/session/authenticate`,
/// `/voip/config`); sau này sẽ chuyển sang `/api/v1` dùng token.
class OdooClient {
  OdooClient(this._dio);

  final Dio _dio;
  String? _baseUrl;
  String? _sessionId;
  int _requestId = 0;

  /// Được gọi khi Odoo cấp session mới (đăng nhập, hoặc Odoo xoay vòng session).
  void Function(String sessionId)? onSessionIdChanged;

  String? get baseUrl => _baseUrl;
  String? get sessionId => _sessionId;

  void configure({required String baseUrl, String? sessionId}) {
    _baseUrl = baseUrl;
    _sessionId = sessionId;
  }

  void clearSession() => _sessionId = null;

  /// Gọi `POST <base><path>` kiểu JSON-RPC, trả về `result`.
  Future<dynamic> rpc(String path, [Map<String, dynamic>? params]) async {
    final base = _baseUrl;
    if (base == null) throw StateError('OdooClient chưa được cấu hình baseUrl');
    try {
      final res = await _dio.post<dynamic>(
        '$base$path',
        data: {
          'jsonrpc': '2.0',
          'method': 'call',
          'params': params ?? <String, dynamic>{},
          'id': ++_requestId,
        },
        options: Options(
          headers: {
            if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
          },
        ),
      );
      _captureSession(res);
      final body = res.data;
      if (body is! Map) {
        throw const ApiException(
          'Máy chủ trả về dữ liệu không hợp lệ. Kiểm tra lại địa chỉ Odoo.',
        );
      }
      if (body['error'] != null) throw _mapOdooError(body['error']);
      return body['result'];
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  void _captureSession(Response<dynamic> res) {
    final cookies = res.headers['set-cookie'];
    if (cookies == null) return;
    for (final c in cookies) {
      if (c.startsWith('session_id=')) {
        final value = c.substring('session_id='.length).split(';').first;
        if (value.isNotEmpty && value != _sessionId) {
          _sessionId = value;
          onSessionIdChanged?.call(value);
        }
      }
    }
  }

  ApiException _mapOdooError(dynamic error) {
    final map = error is Map ? error : const {};
    final data = map['data'] is Map ? map['data'] as Map : const {};
    final name = '${data['name'] ?? ''}';
    final message = '${data['message'] ?? map['message'] ?? ''}';

    if (name.contains('SessionExpired')) return const SessionExpiredException();
    if (name.contains('AccessDenied') || message == 'Access Denied') {
      return const AuthException('Sai tên đăng nhập hoặc mật khẩu.');
    }
    if (message.toLowerCase().contains('database') &&
        message.toLowerCase().contains('not')) {
      return const ApiException('Không tìm thấy database này trên máy chủ Odoo.');
    }
    return ApiException(
      message.isEmpty ? 'Máy chủ Odoo báo lỗi không rõ nguyên nhân.' : message,
    );
  }

  ApiException _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          'Máy chủ phản hồi quá lâu. Kiểm tra mạng và địa chỉ Odoo.',
        );
      case DioExceptionType.badCertificate:
        return const ApiException(
          'Chứng chỉ HTTPS của máy chủ không hợp lệ hoặc không khớp tên miền.',
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          'Không kết nối được máy chủ. Kiểm tra địa chỉ Odoo và kết nối mạng '
          '(máy ảo Android dùng 10.0.2.2 thay cho localhost).',
        );
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 404) {
          return const ApiException(
            'Không tìm thấy đường dẫn trên máy chủ (sai địa chỉ Odoo hoặc chưa '
            'cài module VoIP).',
          );
        }
        return ApiException('Máy chủ trả về lỗi HTTP $code.');
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return ApiException('Lỗi mạng: ${e.message ?? 'không xác định'}');
    }
  }
}

Dio buildDio(AppConfig config) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );
  if (config.allowBadCertificate) {
    // Chỉ dev (AppConfig đã chặn ở prod): cho phép chứng chỉ tự ký khi thử trong LAN.
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      },
    );
  }
  return dio;
}

final odooClientProvider = Provider<OdooClient>(
  (ref) => OdooClient(buildDio(ref.watch(appConfigProvider))),
);
