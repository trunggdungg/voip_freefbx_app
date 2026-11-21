/// Cấu hình SIP của người dùng hiện tại, lấy từ Odoo (`/voip/config`).
/// Chỉ giữ trong bộ nhớ, không ghi xuống máy.
class VoipConfig {
  const VoipConfig({required this.server, required this.user});

  final VoipServerConfig server;
  final VoipUserConfig user;

  factory VoipConfig.fromJson(Map<String, dynamic> json) {
    final server = json['server'];
    final user = json['user'];
    if (server is! Map || user is! Map) {
      throw const FormatException('Thiếu mục server hoặc user');
    }
    return VoipConfig(
      server: VoipServerConfig.fromJson(Map<String, dynamic>.from(server)),
      user: VoipUserConfig.fromJson(Map<String, dynamic>.from(user)),
    );
  }
}

class VoipServerConfig {
  const VoipServerConfig({
    required this.host,
    this.websocketUrl,
    this.port,
    this.realm,
    this.useTls = true,
  });

  final String host;
  final String? websocketUrl;
  final int? port;
  final String? realm;
  final bool useTls;

  factory VoipServerConfig.fromJson(Map<String, dynamic> json) {
    String? str(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty || s == 'false') ? null : s;
    }

    return VoipServerConfig(
      host: str(json['host']) ?? '',
      websocketUrl: str(json['websocket_url']),
      port: json['port'] is int ? json['port'] as int : null,
      realm: str(json['realm']),
      useTls: json['use_tls'] != false,
    );
  }

  /// URL WSS trỏ về máy chủ không truy cập được từ điện thoại.
  bool get isLoopback {
    final host = Uri.tryParse(websocketUrl ?? '')?.host ?? this.host;
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }
}

class VoipUserConfig {
  const VoipUserConfig({
    required this.username,
    required this.password,
    required this.displayName,
    this.autoAnswer = false,
  });

  final String username;
  final String password;
  final String displayName;
  final bool autoAnswer;

  factory VoipUserConfig.fromJson(Map<String, dynamic> json) {
    final username = json['username']?.toString() ?? '';
    final password = json['password']?.toString() ?? '';
    if (username.isEmpty || password.isEmpty) {
      throw const FormatException('Thiếu extension hoặc mật khẩu SIP');
    }
    return VoipUserConfig(
      username: username,
      password: password,
      displayName: json['display_name']?.toString() ?? username,
      autoAnswer: json['auto_answer'] == true,
    );
  }

  /// Không in mật khẩu SIP ra log.
  @override
  String toString() => 'VoipUserConfig($username, password: ***)';
}
