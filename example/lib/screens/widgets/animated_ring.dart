import 'dart:math';
import 'package:flutter/material.dart';

/// Flutter version of the native AnimatedCallAvatarView.
///
/// Draws a rotating 90° arc with glow effects around a child widget.
/// When [isConnected] is true, the animation stops and shows a static ring.
class AnimatedRing extends StatefulWidget {
  /// The widget to display inside the ring (e.g., caller initials or icon).
  final Widget child;

  /// Whether the call is connected. Stops animation when true.
  final bool isConnected;

  /// Outer diameter of the ring.
  final double size;

  const AnimatedRing({
    super.key,
    required this.child,
    this.isConnected = false,
    this.size = 160,
  });

  @override
  State<AnimatedRing> createState() => _AnimatedRingState();
}

class _AnimatedRingState extends State<AnimatedRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    if (!widget.isConnected) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConnected && !oldWidget.isConnected) {
      _controller.stop();
    } else if (!widget.isConnected && oldWidget.isConnected) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _RingPainter(
              progress: _controller.value,
              isConnected: widget.isConnected,
            ),
            child: child,
          );
        },
        child: Center(child: widget.child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final bool isConnected;

  _RingPainter({required this.progress, required this.isConnected});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 14;

    // Track ring (dark blue)
    final trackPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF346299);

    // Track glow
    final trackGlowPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0x40346299)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawCircle(center, radius, trackGlowPaint);
    canvas.drawCircle(center, radius, trackPaint);

    if (!isConnected) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final startAngle = progress * 2 * pi - pi / 2;
      const sweepAngle = pi / 2; // 90 degrees

      // Outer glow
      final outerGlowPaint = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x407AAEE0)
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 24);

      // Inner glow
      final innerGlowPaint = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x807AAEE0)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);

      // Solid segment
      final segmentPaint = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF7AAEE0);

      canvas.drawArc(rect, startAngle, sweepAngle, false, outerGlowPaint);
      canvas.drawArc(rect, startAngle, sweepAngle, false, innerGlowPaint);
      canvas.drawArc(rect, startAngle, sweepAngle, false, segmentPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isConnected != isConnected;
  }
}
