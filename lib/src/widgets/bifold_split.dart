import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../models.dart';
import 'bifold_scope.dart';

/// The width at which two panes stop being cramped, in logical pixels.
///
/// Used wherever this package has to decide whether there is room for two
/// panes without the platform having reported a size class — on a flat
/// display, on a tablet, on desktop, and on any device with no native fold
/// support at all.
///
/// 600 is Material's own compact-to-medium boundary and the width at which
/// Android reports a non-compact window size class, so a layout that follows
/// it agrees with the rest of the system rather than inventing a third
/// opinion. It is deliberately a single constant: [BifoldSplit] and
/// `BifoldScaffold` both consult it, and two different numbers would make
/// them disagree about the same window.
const double kBifoldRegularWidthBreakpoint = 600.0;

/// What [BifoldSplit] does when there is no active division to split across.
enum BifoldSplitFallback {
  /// Side by side where there is room, stacked where there is not.
  ///
  /// This is the default. "Room" is [FoldInfo.isRegular] when the platform
  /// reports size classes, and the available width against
  /// [kBifoldRegularWidthBreakpoint] when it does not — which is the case on
  /// a device with no native fold support, including desktop and web.
  ///
  /// This is what makes the widget correct on an open foldable. A fold is
  /// only reported as *active* while the device is part-way open, so a flat
  /// inner display — the very shape a two-pane layout is for — takes this
  /// path rather than the splitting one.
  adaptive,

  /// Stack the panes vertically, [BifoldSplit.start] above [BifoldSplit.end].
  ///
  /// Matches how the platform's own split arrangement collapses when the
  /// device is shut. This was the default before 1.0.0, where it put two
  /// panes one above the other on a tablet-sized open display.
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
    this.fallback = BifoldSplitFallback.adaptive,
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
  /// on every non-foldable device — which is to say most of the time, because
  /// a division is only active while the device is part-way open. Defaults to
  /// [BifoldSplitFallback.adaptive].
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
          return _buildFallback(size, info);
        }

        _scheduleMeasure();

        // Translate the region from view coordinates into this widget's.
        // `frame` is already the full area to avoid: the platform reports it
        // with the margins included, so inflating it again would double-count
        // the clearance and push both panes too far apart.
        final Rect avoid = division.frame.shift(-_viewOffset);

        final bool spansThisBox = _spans(avoid, size, division.isHorizontal);
        if (!spansThisBox) {
          return _buildFallback(size, info);
        }

        return division.isHorizontal
            ? _buildHorizontalSplit(size, avoid, info)
            : _buildVerticalSplit(size, avoid, info);
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

  Widget _buildHorizontalSplit(Size size, Rect avoid, FoldInfo info) {
    final double startHeight = avoid.top.clamp(0.0, size.height);
    final double endTop = avoid.bottom.clamp(0.0, size.height);
    final double endHeight = size.height - endTop;

    // The crease can sit hard against an edge when the split does not fill the
    // view. With nothing left for one pane, a split would be worse than the
    // fallback.
    if (startHeight <= 0 || endHeight <= 0) {
      return _buildFallback(size, info);
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

  Widget _buildVerticalSplit(Size size, Rect avoid, FoldInfo info) {
    final double startWidth = avoid.left.clamp(0.0, size.width);
    final double endLeft = avoid.right.clamp(0.0, size.width);
    final double endWidth = size.width - endLeft;

    if (startWidth <= 0 || endWidth <= 0) {
      return _buildFallback(size, info);
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

  Widget _buildFallback(Size size, FoldInfo info) {
    switch (widget.fallback) {
      case BifoldSplitFallback.adaptive:
        // Prefer what the platform says over what the box measures: a size
        // class accounts for the whole window, while this widget may have
        // been handed a fraction of it. Fall back to the width only where no
        // size class was reported at all.
        final bool roomForTwo =
            info.horizontalSizeClass == FoldSizeClass.unspecified
                ? size.width >= kBifoldRegularWidthBreakpoint
                : info.isRegular;
        return roomForTwo ? _sideBySide() : _stacked();
      case BifoldSplitFallback.startOnly:
        return widget.start;
      case BifoldSplitFallback.stack:
        return _stacked();
      case BifoldSplitFallback.sideBySide:
        return _sideBySide();
    }
  }

  Widget _stacked() => Column(
        children: <Widget>[
          Expanded(child: widget.start),
          if (widget.spacing > 0) SizedBox(height: widget.spacing),
          Expanded(child: widget.end),
        ],
      );

  Widget _sideBySide() => Row(
        children: <Widget>[
          Expanded(child: widget.start),
          if (widget.spacing > 0) SizedBox(width: widget.spacing),
          Expanded(child: widget.end),
        ],
      );
}
