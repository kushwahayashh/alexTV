import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

const int _spokes = 12;

/// Apple-style activity spinner: a ring of 12 tapered spokes with a bright
/// leader stepping around the circle, leaving a trailing fade. The fade is a
/// solid grey→white color ramp (no transparency): the leader is pure white,
/// each older spoke steps back toward the grey base color.
///
/// Ported 1:1 from the React prototype's Spinner.tsx and the native player's
/// AppleSpinner so every surface shows the same loader. [size] is in design
/// units — the app-wide DesignScaler upscales it to the TV's real resolution.
class AppleSpinner extends StatefulWidget {
  final double size;
  final Color color;
  const AppleSpinner({super.key, this.size = 36, this.color = AppColors.muted});

  @override
  State<AppleSpinner> createState() => _AppleSpinnerState();
}

class _AppleSpinnerState extends State<AppleSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
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
        builder: (context, _) {
          // Stepped rotation: 12 discrete jumps per second (matches CSS steps(12)).
          final leader = (_controller.value * _spokes).floor() % _spokes;
          return CustomPaint(
            painter: _SpinnerPainter(leader: leader, color: widget.color),
          );
        },
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  final int leader;
  final Color color;
  _SpinnerPainter({required this.leader, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final spokeW = size.width * 0.08;
    final spokeLen = size.height * 0.26;
    final radius = size.width / 2 - spokeLen / 2;
    final half = spokeLen / 2;
    for (var i = 0; i < _spokes; i++) {
      // Trailing fade as a grey→white ramp: leader (t=1) is white, each older
      // spoke steps back toward the grey base. Fully opaque.
      final dist = ((leader - i) + _spokes) % _spokes;
      final t = (_spokes - dist) / _spokes;
      final angle = (i * (2 * math.pi / _spokes)) - math.pi / 2;
      final ex = cx + radius * math.cos(angle);
      final ey = cy + radius * math.sin(angle);
      final ux = math.cos(angle);
      final uy = math.sin(angle);
      final paint = Paint()
        ..color = Color.lerp(color, Colors.white, t)!
        ..strokeWidth = spokeW
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(ex - ux * half, ey - uy * half),
        Offset(ex + ux * half, ey + uy * half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) =>
      old.leader != leader || old.color != color;
}
