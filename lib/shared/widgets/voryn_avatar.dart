import 'package:flutter/material.dart';

import '../../core/theme/voryn_theme.dart';
import 'voryn_presence.dart';

enum VorynAvatarSize {
  small(36),
  medium(48),
  large(64),
  xlarge(88);

  const VorynAvatarSize(this.value);
  final double value;
}

class VorynAvatar extends StatelessWidget {
  const VorynAvatar({
    super.key,
    required this.initials,
    this.size = VorynAvatarSize.medium,
    this.imageProvider,
    this.presenceStatus,
  });

  final String initials;
  final VorynAvatarSize size;
  final ImageProvider? imageProvider;
  final VorynPresenceStatus? presenceStatus;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final dimension = size.value;

    return SizedBox.square(
      dimension: dimension,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: imageProvider == null ? colors.accentGradient : null,
              image: imageProvider == null
                  ? null
                  : DecorationImage(image: imageProvider!, fit: BoxFit.cover),
              border: Border.all(color: colors.border),
            ),
            child: Center(
              child: imageProvider == null
                  ? Text(
                      initials,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: dimension * 0.34,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : null,
            ),
          ),
          if (presenceStatus != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: VorynPresenceDot(status: presenceStatus!, bordered: true),
            ),
        ],
      ),
    );
  }
}
