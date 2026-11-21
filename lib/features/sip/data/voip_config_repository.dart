import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/network/odoo_client.dart';
import '../domain/voip_config.dart';

abstract class VoipConfigRepository {
  Future<VoipConfig> fetch();
}

/// Dùng endpoint sẵn có `/voip/config` của module `voip_webrtc_freepbx`.
class OdooVoipConfigRepository implements VoipConfigRepository {
  OdooVoipConfigRepository(this._client);

  final OdooClient _client;

  @override
  Future<VoipConfig> fetch() async {
    final result = await _client.rpc('/voip/config');
    if (result is! Map) {
      throw const ApiException('Phản hồi cấu hình VoIP không hợp lệ.');
    }
    if (result['success'] != true) {
      throw VoipNotConfiguredException(
        '${result['error'] ?? 'Tài khoản này chưa được cấu hình điện thoại VoIP.'}',
      );
    }
    final config = result['config'];
    if (config is! Map) {
      throw const ApiException('Phản hồi cấu hình VoIP thiếu dữ liệu.');
    }
    try {
      return VoipConfig.fromJson(Map<String, dynamic>.from(config));
    } on FormatException catch (e) {
      throw ApiException('Cấu hình VoIP không đầy đủ: ${e.message}.');
    }
  }
}

final voipConfigRepositoryProvider = Provider<VoipConfigRepository>(
  (ref) => OdooVoipConfigRepository(ref.watch(odooClientProvider)),
);
