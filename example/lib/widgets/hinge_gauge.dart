import 'dart:math' as math;

import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';

/// A large, animated read-out of the hinge angle.
///
/// Draws the device in profile — two panels meeting at the hinge, opened to
/// the angle the platform is reporting — beside the figure itself. The panels
/// are symmetric about vertical, so a shut device points straight up and a
/// flat one lies horizontal, which reads at a glance in a screen recording.
///
/// The angle is tweened between platform updates so folding looks continuous
/// rather than stepping, and it degrades to the pose alone on a device that
/// reports no angle.
class HingeGauge extends StatelessWidget {
  /// Creates a hinge read-out for [info].
  const HingeGauge({required this.info, super.key});

  /// The fold state to display.
  final FoldInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radians = info.hingeAngle;
    final degrees = info.hingeAngleDegrees;
    final live = degrees != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            scheme.surfaceContainerHighest,
            scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          ],
        ),
      ),
      child: Row(
        children: <Widget>[
          // The profile drawing.
          SizedBox(
            width: 108,
            height: 78,
            child: TweenAnimationBuilder<double>(
              // Tween on the raw radians so the sweep is linear in angle.
              tween: Tween<double>(end: radians ?? 0),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => CustomPaint(
                painter: _HingePainter(
                  radians: value,
                  active: live,
                  accent: scheme.primary,
                  dim: scheme.outlineVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          // The figure.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: degrees ?? 0),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => Text(
                        live ? value.toStringAsFixed(0) : '--',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: live ? scheme.primary : scheme.outline,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      '°',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w300,
                        color: live ? scheme.primary : scheme.outline,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      info.pose.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  live
                      ? 'hinge angle, live from the platform'
                      : 'no hinge on this device',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the device in profile at a given hinge angle.
class _HingePainter extends CustomPainter {
  _HingePainter({
    required this.radians,
    required this.active,
    required this.accent,
    required this.dim,
  });

  /// Hinge angle in radians. Zero is shut, pi is flat.
  final double radians;

  /// Whether the platform is actually reporting an angle.
  final bool active;

  final Color accent;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset pivot = Offset(size.width / 2, size.height * 0.78);
    final double arm = size.height * 0.62;
    final Color colour = active ? accent : dim;

    // Panels sit symmetrically about vertical, so the total angle between them
    // is the hinge angle: shut points both straight up, flat lays them level.
    // Canvas y grows downward, hence the negated sine.
    final double half = radians / 2;
    final Offset left =
        pivot + Offset(-math.sin(half) * arm, -math.cos(half) * arm);
    final Offset right =
        pivot + Offset(math.sin(half) * arm, -math.cos(half) * arm);

    // The sweep between the panels.
    if (radians > 0.01) {
      final double sweepRadius = arm * 0.42;
      canvas.drawArc(
        Rect.fromCircle(center: pivot, radius: sweepRadius),
        -math.pi / 2 - half,
        radians,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = colour.withValues(alpha: 0.35),
      );
    }

    final Paint panel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = colour;

    // A soft glow under the panels so the shape reads on a dark background.
    if (active) {
      final Paint glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..color = colour.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas
        ..drawLine(pivot, left, glow)
        ..drawLine(pivot, right, glow);
    }

    canvas
      ..drawLine(pivot, left, panel)
      ..drawLine(pivot, right, panel)
      // The hinge itself.
      ..drawCircle(pivot, 4.5, Paint()..color = colour)
      ..drawCircle(
        pivot,
        4.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = colour.withValues(alpha: 0.4),
      );
  }

  @override
  bool shouldRepaint(_HingePainter oldDelegate) =>
      oldDelegate.radians != radians ||
      oldDelegate.active != active ||
      oldDelegate.accent != accent ||
      oldDelegate.dim != dim;
}
