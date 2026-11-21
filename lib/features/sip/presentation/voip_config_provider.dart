import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/voip_config_repository.dart';
import '../domain/voip_config.dart';

/// Cấu hình SIP của người dùng đang đăng nhập; tải lại khi đổi tài khoản.
final voipConfigProvider = FutureProvider.autoDispose<VoipConfig>((ref) async {
  final session = ref.watch(authControllerProvider).value;
  if (session == null) throw const SessionExpiredException();
  try {
    return await ref.watch(voipConfigRepositoryProvider).fetch();
  } on SessionExpiredException {
    // Phiên hết hạn: đưa về màn đăng nhập.
    Future.microtask(() => ref.read(authControllerProvider.notifier).sessionExpired());
    rethrow;
  }
});
