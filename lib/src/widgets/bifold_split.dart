import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../models.dart';
import 'bifold_scope.dart';

/// What [BifoldSplit] does when there is no active division to split across.
enum BifoldSplitFallback {
  /// Stack the panes vertically, [BifoldSplit.start] above [BifoldSplit.end].
  ///
  /// This is the default, and matches how the platform's own split
  /// arrangement collapses when the device is shut.
  stack,

  /// Place the panes side by side, splitting the space evenly.
  ///
  /// Useful on a flat inner display, where there is plenty of width but no
  /// crease to align to.
  sideBySide,

  /// Show only [BifoldSplit.start], discarding the other pane.
  ///
  /// Appropriate for a primary/detail pair on the outer display, where there
  /// is not enough room for both.
  startOnly,
}

/// Lays two panes out on either side of the fold.
///
/// When the device is part-way open and the platform reports an active
/// division across this widget, the panes are placed on either side of it,
/// clear of the crease and its margins. Otherwise the panes fall back to
/// [fallback], which stacks them by default.
///
/// ```dart
/// BifoldSplit(
///   start: PageView(controller: left),
///   end: PageView(controller: right),
/// )
/// ```
///
/// This is modelled on how the platform's split arrangement behaves. It is not
/// a binding to that API, and does not reproduce its animations.
///
/// ## Coordinates
///
/// Reserved regions are reported relative to the Flutter view, while this
/// widget is laid out wherever its parent puts it. The translation between the
/// two is handled automatically, but it needs one layout pass to measure, so a
/// split that is not at the view origin resolves on the frame after it first
/// appears. Regions themselves also arrive after the first layout pass, so
/// this costs nothing in practice.
class BifoldSplit extends StatefulWidget {
  /// Creates a two-pane layout that aligns to the fold.
  const BifoldSplit({
    required this.start,
    required this.end,
    this.fallback = BifoldSplitFallback.stack,
    this.spacing = 0.0,
    super.key,
  });

  /// The pane above, or to the left of, the fold.
  final Widget start;

  /// The pane below, or to the right of, the fold.
  final Widget end;

  /// How to lay out when there is no active division to split across.
  ///
  /// This applies on the outer display, while the device is flat or shut, and
  /// on every non-foldable device.
  final BifoldSplitFallback fallback;

  /// Gap between the panes when [fallback] positions them, in logical pixels.
  ///
  /// Ignored when splitting across a real division, where the crease and its
  /// margins already separate the panes.
  final double spacing;

  @override
  State<BifoldSplit> createState() => _BifoldSplitState();
}

class _BifoldSplitState extends State<BifoldSplit> {
  /// This widget's offset from the view origin, in logical pixels.
  ///
  /// Measured after layout, because it cannot be known during the build that
  /// produces that layout. Until it is measured the widget lays out as though
  /// it sits at the view origin, which is correct for the common case of a
  /// split that fills the view.
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
      final Offset measured = _measure();
      if (measured != _viewOffset) {
        setState(() => _viewOffset = measured);
      }
    });
  }

  Offset _measure() {
    final RenderObject? object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return _viewOffset;
    }
    return object.localToGlobal(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final FoldInfo info = Bifold.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        final FoldRegion? division = info.division;

        // An unbounded constraint gives no geometry to split, and a division
        // that does not span this box cannot separate it.
        if (division == null || !size.isFinite || size.isEmpty) {
          return _buildFallback(size);
        }

        _scheduleMeasure();

        // Translate the region from view coordinates into this widget's.
        // `frame` is already the full area to avoid: the platform reports it
        // with the margins included, so inflating it again would double-count
        // the clearance and push both panes too far apart.
        final Rect avoid = division.frame.shift(-_viewOffset);

        final bool spansThisBox = _spans(avoid, size, division.isHorizontal);
        if (!spansThisBox) {
          return _buildFallback(size);
        }

        return division.isHorizontal
            ? _buildHorizontalSplit(size, avoid)
            : _buildVerticalSplit(size, avoid);
      },
    );
  }

  /// Whether [frame] crosses the whole of a box of [size] on its long axis.
  ///
  /// A division reported for the view may sit entirely outside this widget —
  /// above a split placed in the lower half of the screen, say — in which case
  /// there is nothing to split across.
  static bool _spans(Rect frame, Size size, bool isHorizontal) {
    const double tolerance = 1.0;
    if (isHorizontal) {
      return frame.left <= tolerance &&
          frame.right >= size.width - tolerance &&
          frame.bottom > 0 &&
          frame.top < size.height;
    }
    return frame.top <= tolerance &&
        frame.bottom >= size.height - tolerance &&
        frame.right > 0 &&
        frame.left < size.width;
  }

  Widget _buildHorizontalSplit(Size size, Rect avoid) {
    final double startHeight = avoid.top.clamp(0.0, size.height);
    final double endTop = avoid.bottom.clamp(0.0, size.height);
    final double endHeight = size.height - endTop;

    // The crease can sit hard against an edge when the split does not fill the
    // view. With nothing left for one pane, a split would be worse than the
    // fallback.
    if (startHeight <= 0 || endHeight <= 0) {
      return _buildFallback(size);
    }

    return Stack(
      children: <Widget>[
        Positioned(
          left: 0,
          top: 0,
          width: size.width,
          height: startHeight,
          child: widget.start,
        ),
        Positioned(
          left: 0,
          top: endTop,
          width: size.width,
          height: endHeight,
          child: widget.end,
        ),
      ],
    );
  }

  Widget _buildVerticalSplit(Size size, Rect avoid) {
    final double startWidth = avoid.left.clamp(0.0, size.width);
    final double endLeft = avoid.right.clamp(0.0, size.width);
    final double endWidth = size.width - endLeft;

    if (startWidth <= 0 || endWidth <= 0) {
      return _buildFallback(size);
    }

    return Stack(
      children: <Widget>[
        Positioned(
          left: 0,
          top: 0,
          width: startWidth,
          height: size.height,
          child: widget.start,
        ),
        Positioned(
          left: endLeft,
          top: 0,
          width: endWidth,
          height: size.height,
          child: widget.end,
        ),
      ],
    );
  }

  Widget _buildFallback(Size size) {
    switch (widget.fallback) {
      case BifoldSplitFallback.startOnly:
        return widget.start;
      case BifoldSplitFallback.stack:
        return Column(
          children: <Widget>[
            Expanded(child: widget.start),
            if (widget.spacing > 0) SizedBox(height: widget.spacing),
            Expanded(child: widget.end),
          ],
        );
      case BifoldSplitFallback.sideBySide:
        return Row(
          children: <Widget>[
            Expanded(child: widget.start),
            if (widget.spacing > 0) SizedBox(width: widget.spacing),
            Expanded(child: widget.end),
          ],
        );
    }
  }
}
