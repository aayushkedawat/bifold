import 'package:flutter/widgets.dart';

import '../models.dart';
import 'bifold_scope.dart';

/// A grid whose rows stop cleanly at the fold instead of straddling it.
///
/// A conventional [GridView] lays tiles out in a continuous flow, so on a
/// creased display a row of cards can end up half on each side of the fold,
/// with its content bent through the middle. This grid treats an active
/// division as a hard break: tiles fill the space before it, then resume after
/// it, and no tile is ever drawn across the crease.
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
        final double width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final int columns = _columnsFor(width - padding.horizontal);

        final FoldRegion? division = info.division;
        final bool splitHorizontally =
            division != null &&
            division.isHorizontal &&
            constraints.hasBoundedHeight &&
            division.isSeparating(Size(width, constraints.maxHeight));

        if (!splitHorizontally) {
          return _buildGrid(children, columns, scrollable: true);
        }

        // Fill the space above the crease with as many whole rows as fit, then
        // start the remainder below it.
        final double rowHeight = _rowHeight(width - padding.horizontal, columns);
        final int rowsAbove = rowHeight <= 0
            ? 0
            : (division.frame.top - padding.top) ~/ rowHeight;
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
      },
    );
  }

  int _columnsFor(double available) {
    if (available <= 0) {
      return 1;
    }
    final int columns = ((available + spacing) / (tileExtent + spacing)).floor();
    return columns < 1 ? 1 : columns;
  }

  double _rowHeight(double available, int columns) {
    final double tile =
        (available - spacing * (columns - 1)) / columns;
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
      physics: scrollable
          ? null
          : const NeverScrollableScrollPhysics(),
      shrinkWrap: !scrollable,
      children: tiles,
    );
  }
}
