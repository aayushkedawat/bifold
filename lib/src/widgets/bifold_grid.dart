import 'package:flutter/widgets.dart';

import '../models.dart';
import 'bifold_scope.dart';

/// A grid whose tiles stop cleanly at the fold instead of straddling it.
///
/// A conventional [GridView] lays tiles out in a continuous flow, so on a
/// creased display a row of cards can end up half on each side of the fold,
/// with its content bent through the middle. This grid treats an active
/// division as a hard break: tiles fill the space on one side of it, then
/// resume on the other, and no tile is ever drawn across the crease.
///
/// The break follows whichever way the crease runs. A flip-style device folds
/// the display into a top and a bottom part, which breaks the rows; a
/// book-style device folds it into a left and a right part, which breaks the
/// columns.
///
/// ```dart
/// BifoldGrid(
///   tileExtent: 160,
///   children: photos.map(PhotoTile.new).toList(),
/// )
/// ```
///
/// With no active division — shut, flat, or a device that does not fold — it
/// behaves as an ordinary wrapping grid, so it is safe to use unconditionally.
class BifoldGrid extends StatelessWidget {
  /// Creates a grid that respects the fold.
  const BifoldGrid({
    required this.children,
    this.tileExtent = 150.0,
    this.spacing = 8.0,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// The tiles to lay out.
  final List<Widget> children;

  /// Target width and height of a tile, in logical pixels.
  ///
  /// Columns are computed from the available width, so the real tile width is
  /// this rounded to fit.
  final double tileExtent;

  /// Gap between tiles, in logical pixels.
  final double spacing;

  /// Padding around the whole grid.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final FoldInfo info = Bifold.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Either axis may be unbounded — a grid in a scrolling parent — and
        // `isSeparating` still deserves a real display size to answer with.
        final Size window = MediaQuery.sizeOf(context);
        final double width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : window.width;
        final double height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : window.height;

        final FoldRegion? division = info.division;
        if (division == null || !division.isSeparating(Size(width, height))) {
          return _plainGrid(width);
        }

        // Splitting stacks the far side in an `Expanded`, so the axis it
        // stacks on has to be bounded. An unbounded one means the parent is
        // scrolling this grid anyway, and the plain grid is the right answer.
        if (division.isHorizontal) {
          return constraints.hasBoundedHeight
              ? _splitRows(division, width)
              : _plainGrid(width);
        }
        return constraints.hasBoundedWidth
            ? _splitColumns(division, width, height)
            : _plainGrid(width);
      },
    );
  }

  Widget _plainGrid(double width) => _buildGrid(
        children,
        _columnsFor(width - padding.horizontal),
        scrollable: true,
      );

  /// Breaks the rows at a crease running across the display.
  Widget _splitRows(FoldRegion division, double width) {
    final double available = width - padding.horizontal;
    final int columns = _columnsFor(available);

    // Fill the space above the crease with as many whole rows as fit, then
    // start the remainder below it.
    final double rowHeight = _rowHeight(available, columns);
    final int rowsAbove =
        rowHeight <= 0 ? 0 : (division.frame.top - padding.top) ~/ rowHeight;
    final int countAbove = (rowsAbove * columns).clamp(0, children.length);

    return Column(
      children: <Widget>[
        SizedBox(
          height: division.frame.top,
          child: _buildGrid(
            children.sublist(0, countAbove),
            columns,
            scrollable: false,
          ),
        ),
        SizedBox(height: division.frame.height),
        Expanded(
          child: _buildGrid(
            children.sublist(countAbove),
            columns,
            scrollable: true,
          ),
        ),
      ],
    );
  }

  /// Breaks the columns at a crease running down the display.
  ///
  /// The two sides are not the same width — the crease sits wherever the
  /// hardware puts it — so each works out its own column count. A single count
  /// taken from the whole width would overflow each side; one taken from the
  /// narrow side would leave the wide side cramped.
  Widget _splitColumns(FoldRegion division, double width, double height) {
    final Rect frame = division.frame;

    final double availableLeft = frame.left - padding.horizontal;
    final int columnsLeft = _columnsFor(availableLeft);

    // As many whole rows as the height fits, so the first side holds only what
    // it can show without scrolling and the rest stays scrollable beside it.
    final double rowHeight = _rowHeight(availableLeft, columnsLeft);
    final int rowsLeft =
        rowHeight <= 0 ? 0 : (height - padding.vertical) ~/ rowHeight;
    final int countLeft = (columnsLeft * rowsLeft).clamp(0, children.length);

    return Row(
      children: <Widget>[
        SizedBox(
          width: frame.left,
          child: _buildGrid(
            children.sublist(0, countLeft),
            columnsLeft,
            scrollable: false,
          ),
        ),
        SizedBox(width: frame.width),
        Expanded(
          child: _buildGrid(
            children.sublist(countLeft),
            _columnsFor(width - frame.right - padding.horizontal),
            scrollable: true,
          ),
        ),
      ],
    );
  }

  int _columnsFor(double available) {
    if (available <= 0) {
      return 1;
    }
    final int columns =
        ((available + spacing) / (tileExtent + spacing)).floor();
    return columns < 1 ? 1 : columns;
  }

  double _rowHeight(double available, int columns) {
    final double tile = (available - spacing * (columns - 1)) / columns;
    return tile + spacing;
  }

  Widget _buildGrid(
    List<Widget> tiles,
    int columns, {
    required bool scrollable,
  }) {
    if (tiles.isEmpty) {
      return const SizedBox.shrink();
    }
    return GridView.count(
      padding: padding,
      crossAxisCount: columns,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      shrinkWrap: !scrollable,
      children: tiles,
    );
  }
}
