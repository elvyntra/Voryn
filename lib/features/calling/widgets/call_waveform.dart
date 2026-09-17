import 'dart:math' as math;
import 'package:flutter/material.dart';

class CallWaveform extends StatefulWidget {
  const CallWaveform({super.key, this.isActive = true, this.color});

  final bool isActive;
  final Color? color;

  @override
  State<CallWaveform> createState() => _CallWaveformState();
}

class _CallWaveformState extends State<CallWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const List<double> _baseHeights = [8, 14, 22, 16, 26, 18, 10];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(CallWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waveColor = widget.color ?? const Color(0xFFA78BFA);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          height: 28,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_baseHeights.length, (index) {
              final phase = (index * 0.45);
              final animFactor = widget.isActive
                  ? (math.sin((_controller.value * 2 * math.pi) + phase) + 1) /
                            2 *
                            0.6 +
                        0.4
                  : 0.35;
              final height = _baseHeights[index] * animFactor;

              return Container(
                width: 3.5,
                height: math.max(4.0, height),
                margin: const EdgeInsets.symmetric(horizontal: 2.2),
                decoration: BoxDecoration(
                  color: waveColor.withValues(
                    alpha: widget.isActive ? 0.9 : 0.4,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
