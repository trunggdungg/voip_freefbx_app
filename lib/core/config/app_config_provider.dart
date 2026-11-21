import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';

/// Cấu hình môi trường hiện tại. Test có thể override provider này.
final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);
