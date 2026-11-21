import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Chuông báo cuộc gọi đến. Tách thành interface để test không phát âm thanh thật.
abstract class Ringtone {
  Future<void> start();
  Future<void> stop();
}

/// Dùng nhạc chuông mặc định của hệ thống (tôn trọng chế độ im lặng/âm lượng chuông).
class SystemRingtone implements Ringtone {
  final _player = FlutterRingtonePlayer();

  @override
  Future<void> start() async {
    try {
      await _player.playRingtone(looping: true, asAlarm: false);
    } catch (_) {
      // Không phát được chuông thì cuộc gọi vẫn hiện trên màn hình.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }
}

final ringtoneProvider = Provider<Ringtone>((ref) => SystemRingtone());
