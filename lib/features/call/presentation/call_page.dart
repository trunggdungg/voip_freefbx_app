import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/call_session.dart';
import 'call_controller.dart';
import 'dial_pad.dart';

/// Màn hình cuộc gọi đang diễn ra. Tự đóng khi cuộc gọi kết thúc (do router xử lý).
class CallPage extends ConsumerWidget {
  const CallPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callControllerProvider);
    final controller = ref.read(callControllerProvider.notifier);
    final theme = Theme.of(context);

    if (call == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return PopScope(
      // Đang gọi thì phải bấm "Kết thúc", không thoát bằng nút Back.
      canPop: call.isTerminal,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                const CircleAvatar(
                  radius: 44,
                  child: Icon(Icons.person, size: 48),
                ),
                const SizedBox(height: 16),
                Text(
                  call.remoteName?.isNotEmpty == true
                      ? call.remoteName!
                      : call.remoteNumber,
                  key: const ValueKey('call-remote'),
                  style: theme.textTheme.headlineMedium,
                ),
                if (call.remoteName?.isNotEmpty == true)
                  Text(call.remoteNumber, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 8),
                _CallStatusText(call: call),
                const Spacer(),
                if (call.isIncomingRinging)
                  _IncomingActions(
                    onAnswer: () => _answer(context, controller),
                    onReject: controller.reject,
                  )
                else if (!call.isTerminal) ...[
                  Wrap(
                    spacing: 28,
                    runSpacing: 20,
                    alignment: WrapAlignment.center,
                    children: [
                      _RoundAction(
                        icon: call.muted ? Icons.mic_off : Icons.mic,
                        label: 'Tắt tiếng',
                        selected: call.muted,
                        enabled: call.isActive,
                        onTap: controller.toggleMute,
                      ),
                      _RoundAction(
                        icon: Icons.volume_up,
                        label: 'Loa ngoài',
                        selected: call.speakerOn,
                        onTap: controller.toggleSpeaker,
                      ),
                      _RoundAction(
                        icon: Icons.pause,
                        label: 'Giữ máy',
                        selected: call.held,
                        enabled: call.isActive,
                        onTap: controller.toggleHold,
                      ),
                      _RoundAction(
                        icon: Icons.dialpad,
                        label: 'Bàn phím',
                        enabled: call.isActive,
                        onTap: () => _showKeypad(context, controller),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  FloatingActionButton.large(
                    heroTag: 'call-hangup',
                    tooltip: 'Kết thúc',
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                    onPressed: controller.hangup,
                    child: const Icon(Icons.call_end),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _answer(BuildContext context, CallController controller) async {
    try {
      await controller.answer();
    } on CallException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void _showKeypad(BuildContext context, CallController controller) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: DialPad(onKey: controller.sendDtmf),
      ),
    );
  }
}

/// Hai nút lớn khi có cuộc gọi đến: Từ chối (đỏ) và Trả lời (xanh).
class _IncomingActions extends StatelessWidget {
  const _IncomingActions({required this.onAnswer, required this.onReject});

  final VoidCallback onAnswer;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.large(
              heroTag: 'call-reject',
              tooltip: 'Từ chối',
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
              onPressed: onReject,
              child: const Icon(Icons.call_end),
            ),
            const SizedBox(height: 8),
            const Text('Từ chối'),
          ],
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.large(
              heroTag: 'call-answer',
              tooltip: 'Trả lời',
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              onPressed: onAnswer,
              child: const Icon(Icons.call),
            ),
            const SizedBox(height: 8),
            const Text('Trả lời'),
          ],
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: label,
          isSelected: selected,
          onPressed: enabled ? onTap : null,
          icon: Icon(icon),
          selectedIcon: Icon(icon, color: scheme.onPrimary),
          style: selected
              ? IconButton.styleFrom(backgroundColor: scheme.primary)
              : null,
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// Dòng trạng thái: "Đang gọi…", "Đổ chuông…", thời lượng, hoặc kết quả.
class _CallStatusText extends StatefulWidget {
  const _CallStatusText({required this.call});
  final CallSession call;

  @override
  State<_CallStatusText> createState() => _CallStatusTextState();
}

class _CallStatusTextState extends State<_CallStatusText> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_CallStatusText old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  // Chỉ chạy đồng hồ khi đang đàm thoại, để không tạo frame thừa.
  void _syncTicker() {
    final needTicker = widget.call.isActive;
    if (needTicker && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else if (!needTicker) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    return '${h > 0 ? '$h:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final scheme = Theme.of(context).colorScheme;
    final duration = call.durationAt(DateTime.now());

    final String text;
    var color = scheme.onSurfaceVariant;
    switch (call.phase) {
      case CallPhase.dialing:
        text = 'Đang gọi…';
      case CallPhase.ringing:
        text = call.direction == CallDirection.incoming
            ? 'Cuộc gọi đến…'
            : 'Đổ chuông…';
      case CallPhase.active:
        text = call.held
            ? 'Đang giữ máy · ${_fmt(duration ?? Duration.zero)}'
            : _fmt(duration ?? Duration.zero);
      case CallPhase.ended:
        if (call.missed) color = scheme.error;
        text = duration == null
            ? (call.endDetail ?? 'Cuộc gọi kết thúc')
            : 'Cuộc gọi kết thúc · ${_fmt(duration)}';
      case CallPhase.failed:
        text = call.endDetail ?? 'Không gọi được';
        color = scheme.error;
    }
    return Text(
      text,
      key: const ValueKey('call-status'),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
    );
  }
}
