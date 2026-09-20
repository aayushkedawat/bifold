import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../models.dart';
import 'bifold_scope.dart';

/// Draws the reserved regions the platform is reporting, on top of [child].
///
/// This is a diagnostic tool. Wrap it around an app, or any part of one, to
/// see where the fold and the camera cutout actually are, whether each region
/// is active, and how much clearance the platform is asking for:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => BifoldDebugOverlay(child: child!),
///   home: const MyHomePage(),
/// )
/// ```
///
/// Each region is drawn twice: an outline for [FoldRegion.frame], the whole
/// area content should avoid, and a filled band for [FoldRegion.reservedRect],
/// the hardware inside it. The gap between them is the platform's clearance.
/// Active regions are drawn solid, inactive ones faint — the distinction that
/// most often explains why a layout did not react the way it was expected to.
///
/// The overlay ignores pointer events, so the app underneath stays usable.
class BifoldDebugOverlay extends StatefulWidget {
  /// Creates a diagnostic overlay above [child].
  const BifoldDebugOverlay({
    required this.child,
    this.enabled = true,
    this.showLabels = true,
    this.divisionColor = const Color(0xFF00E5FF),
    this.occlusionColor = const Color(0xFFFF4081),
    this.unknownColor = const Color(0xFFFFD740),
    super.key,
  });

  /// The app, or the part of it, to draw over.
  final Widget child;

  /// Whether to draw anything.
  ///
  /// Wire this to a debug switch rather than removing the widget, so the tree
  /// shape stays the same when the overlay is off.
  final bool enabled;

  /// Whether to label each region with its kind, active state and size.
  final bool showLabels;

  /// Colour for [RegionKind.division] regions.
  final Color divisionColor;

  /// Colour for [RegionKind.occlusion] regions.
  final Color occlusionColor;

  /// Colour for regions whose kind this version does not recognise.
  final Color unknownColor;

  @override
  State<BifoldDebugOverlay> createState() => _BifoldDebugOverlayState();
}

class _BifoldDebugOverlayState extends State<BifoldDebugOverlay> {
  Offset _viewOffset = Offset.zero;
  bool _measureScheduled = false;

  void _scheduleMeasure() {
    if (_measureScheduled) {
      return;
    }
    _measureScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) {
        return;
      }
      final RenderObject? object = context.findRenderObject();
      if (object is! RenderBox || !object.attached || !object.hasSize) {
        return;
      }
      final Offset measured = object.localToGlobal(Offset.zero);
      if (measured != _viewOffset) {
        setState(() => _viewOffset = measured);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    final FoldInfo info = Bifold.of(context);
    _scheduleMeasure();

    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _RegionPainter(
                info: info,
                viewOffset: _viewOffset,
                showLabels: widget.showLabels,
                divisionColor: widget.divisionColor,
                occlusionColor: widget.occlusionColor,
                unknownColor: widget.unknownColor,
                textDirection: Directionality.of(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RegionPainter extends CustomPainter {
  _RegionPainter({
    required this.info,
    required this.viewOffset,
    required this.showLabels,
    required this.divisionColor,
    required this.occlusionColor,
    required this.unknownColor,
    required this.textDirection,
  });

  final FoldInfo info;
  final Offset viewOffset;
  final bool showLabels;
  final Color divisionColor;
  final Color occlusionColor;
  final Color unknownColor;
  final TextDirection textDirection;

  static const double _minimumTouchableBand = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    for (final FoldRegion region in info.regions) {
      _paintRegion(canvas, size, region);
    }
    if (showLabels) {
      _paintSummary(canvas, size);
    }
  }

  void _paintRegion(Canvas canvas, Size size, FoldRegion region) {
    final Color color = switch (region.kind) {
      RegionKind.division => divisionColor,
      RegionKind.occlusion => occlusionColor,
      RegionKind.unknown => unknownColor,
    };

    // `frame` is the whole avoid area (margins included); `reservedRect` is
    // the hardware inside it.
    final Rect avoidance = region.frame.shift(-viewOffset);
    final Rect frame = region.reservedRect.shift(-viewOffset);

    // A crease can be reported with zero thickness. Draw it as a hairline so
    // it is visible at all, rather than painting an empty rect.
    final Rect drawnFrame =
        frame.height < _minimumTouchableBand && frame.width > frame.height
            ? Rect.fromLTRB(
                frame.left,
                frame.center.dy - _minimumTouchableBand / 2,
                frame.right,
                frame.center.dy + _minimumTouchableBand / 2,
              )
            : frame.width < _minimumTouchableBand && frame.height > frame.width
                ? Rect.fromLTRB(
                    frame.center.dx - _minimumTouchableBand / 2,
                    frame.top,
                    frame.center.dx + _minimumTouchableBand / 2,
                    frame.bottom,
                  )
                : frame;

    canvas.drawRect(
      drawnFrame,
      Paint()..color = color.withValues(alpha: region.isActive ? 0.55 : 0.18),
    );

    // The avoidance area is only interesting when it differs from the frame.
    if (avoidance != frame) {
      canvas.drawRect(
        avoidance,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = color.withValues(alpha: region.isActive ? 0.9 : 0.35),
      );
    }

    if (showLabels) {
      _paintLabel(canvas, size, region, color, drawnFrame);
    }
  }

  void _paintLabel(
    Canvas canvas,
    Size size,
    FoldRegion region,
    Color color,
    Rect drawnFrame,
  ) {
    final String text = '${region.kind.name}'
        '${region.isActive ? '' : ' (inactive)'}  '
        '${region.frame.width.toStringAsFixed(0)}'
        '×'
        '${region.frame.height.toStringAsFixed(0)}';

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          height: 1.2,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
      textDirection: textDirection,
    )..layout(maxWidth: size.width);

    // Keep the label on screen even when its region is flush with an edge.
    final double dx = (drawnFrame.left + 4).clamp(
      0.0,
      (size.width - painter.width).clamp(0.0, double.infinity),
    );
    final double dy = (drawnFrame.bottom + 2).clamp(
      0.0,
      (size.height - painter.height).clamp(0.0, double.infinity),
    );
    final Offset at = Offset(dx, dy);

    canvas.drawRect(
      Rect.fromLTWH(
          at.dx - 2, at.dy - 1, painter.width + 4, painter.height + 2),
      Paint()..color = const Color(0xCC000000),
    );
    painter.paint(canvas, at);
  }

  void _paintSummary(Canvas canvas, Size size) {
    final String text =
        'bifold  ${info.isFoldable ? 'foldable' : 'not foldable'}  '
        '·  ${info.display.name}  ·  ${info.pose.name}  '
        '·  ${info.regions.length} region'
        '${info.regions.length == 1 ? '' : 's'}';

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 10,
          height: 1.2,
        ),
      ),
      textDirection: textDirection,
    )..layout(maxWidth: size.width);

    final Rect background = Rect.fromLTWH(
      0,
      size.height - painter.height - 4,
      painter.width + 8,
      painter.height + 4,
    );
    canvas
      ..drawRect(background, Paint()..color = const Color(0xCC000000))
      ..save();
    painter.paint(canvas, Offset(4, size.height - painter.height - 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RegionPainter oldDelegate) =>
      oldDelegate.info != info ||
      oldDelegate.viewOffset != viewOffset ||
      oldDelegate.showLabels != showLabels ||
      oldDelegate.divisionColor != divisionColor ||
      oldDelegate.occlusionColor != occlusionColor ||
      oldDelegate.unknownColor != unknownColor ||
      oldDelegate.textDirection != textDirection;
}
