import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sip/presentation/sip_controller.dart';
import '../domain/call_session.dart';
import 'call_controller.dart';
import 'dial_pad.dart';

class DialPage extends ConsumerStatefulWidget {
  const DialPage({super.key});

  @override
  ConsumerState<DialPage> createState() => _DialPageState();
}

class _DialPageState extends ConsumerState<DialPage> {
  String _number = '';
  bool _calling = false;

  Future<void> _call() async {
    setState(() => _calling = true);
    try {
      await ref.read(callControllerProvider.notifier).dial(_number);
    } on CallException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final registered = ref.watch(sipControllerProvider).isRegistered;
    final theme = Theme.of(context);
    final canCall = registered && _number.isNotEmpty && !_calling;

    return Scaffold(
      appBar: AppBar(title: const Text('Bàn phím')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _number.isEmpty ? 'Nhập số điện thoại' : _number,
                        key: const ValueKey('dial-number'),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: _number.isEmpty
                            ? theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.outline,
                              )
                            : theme.textTheme.headlineMedium,
                      ),
                    ),
                    if (_number.isNotEmpty)
                      GestureDetector(
                        onLongPress: () => setState(() => _number = ''),
                        child: IconButton(
                          tooltip: 'Xóa (giữ để xóa hết)',
                          icon: const Icon(Icons.backspace_outlined),
                          onPressed: () => setState(
                            () => _number = _number.substring(
                              0,
                              _number.length - 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!registered)
                Text(
                  'Chưa đăng ký với tổng đài, chưa thể gọi.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              const Spacer(),
              DialPad(onKey: (k) => setState(() => _number += k)),
              const SizedBox(height: 16),
              FloatingActionButton.large(
                heroTag: 'dial-call',
                tooltip: 'Gọi',
                backgroundColor: canCall ? Colors.green : theme.disabledColor,
                foregroundColor: Colors.white,
                onPressed: canCall ? _call : null,
                child: const Icon(Icons.call),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
