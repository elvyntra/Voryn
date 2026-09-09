import 'package:flutter/material.dart';

import '../../core/theme/voryn_theme.dart';

enum VorynPresenceStatus { online, busy, doNotDisturb, offline }

class VorynPresenceDot extends StatelessWidget {
  const VorynPresenceDot({
    super.key,
    required this.status,
    this.bordered = false,
  });

  final VorynPresenceStatus status;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;

    return Container(
      width: bordered ? 14 : 8,
      height: bordered ? 14 : 8,
      decoration: BoxDecoration(
        color: _statusColor(colors),
        shape: BoxShape.circle,
        border: bordered
            ? Border.all(color: colors.background, width: 2)
            : null,
      ),
    );
  }

  Color _statusColor(VorynColors colors) {
    return switch (status) {
      VorynPresenceStatus.online => colors.success,
      VorynPresenceStatus.busy => colors.warning,
      VorynPresenceStatus.doNotDisturb => colors.danger,
      VorynPresenceStatus.offline => colors.textMuted,
    };
  }
}

class VorynPresenceIndicator extends StatelessWidget {
  const VorynPresenceIndicator({
    super.key,
    required this.status,
    required this.label,
  });

  final VorynPresenceStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VorynPresenceDot(status: status),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}
