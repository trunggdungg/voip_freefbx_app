import 'package:flutter/material.dart';

/// Bàn phím số 3x4 dùng cho cả màn hình gọi và bàn phím DTMF trong cuộc gọi.
class DialPad extends StatelessWidget {
  const DialPad({super.key, required this.onKey});

  final void Function(String key) onKey;

  static const _keys = [
    ('1', ''),
    ('2', 'ABC'),
    ('3', 'DEF'),
    ('4', 'GHI'),
    ('5', 'JKL'),
    ('6', 'MNO'),
    ('7', 'PQRS'),
    ('8', 'TUV'),
    ('9', 'WXYZ'),
    ('*', ''),
    ('0', '+'),
    ('#', ''),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      children: [
        for (final (digit, letters) in _keys)
          InkResponse(
            key: ValueKey('key-$digit'),
            onTap: () => onKey(digit),
            // Giữ phím 0 để nhập dấu + (số quốc tế).
            onLongPress: digit == '0' ? () => onKey('+') : null,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(digit, style: theme.textTheme.headlineMedium),
                  if (letters.isNotEmpty)
                    Text(letters, style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
