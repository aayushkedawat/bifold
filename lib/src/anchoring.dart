import 'package:flutter/widgets.dart';

import 'models.dart';
import 'widgets/bifold_scope.dart';

/// Keeps dialogs, popups and sheets off the fold.
///
/// Flutter positions a dialog using an `anchorPoint` when the screen is split
/// by a display feature, but only when `MediaQuery.displayFeatures` is
/// populated — which on iOS it is not. Without help, a dialog on an open
/// foldable lands centred, straddling the crease, with its title on one half
/// and its buttons on the other.
///
/// Pass [bifoldAnchorPoint] to place it in whichever half has more room:
///
/// ```dart
/// showDialog(
///   context: context,
///   anchorPoint: bifoldAnchorPoint(context),
///   builder: (context) => const AlertDialog(title: Text('Hello')),
/// );
/// ```
///
/// Returns null when there is nothing to avoid, which is what `showDialog`
/// expects for its default behaviour, so this is safe to pass unconditionally.
Offset? bifoldAnchorPoint(BuildContext context) {
  final FoldInfo? info = Bifold.maybeOf(context);
  if (info == null) {
    return null;
  }
  final Size size = MediaQuery.sizeOf(context);
  return bifoldAnchorPointFor(info, size);
}

/// The anchor point for [info] on a view of [size], or null if unnecessary.
///
/// Separated from [bifoldAnchorPoint] so the choice can be tested without a
/// widget tree.
@visibleForTesting
Offset? bifoldAnchorPointFor(FoldInfo info, Size size) {
  final FoldRegion? division = info.division;
  if (division == null || !division.isSeparating(size)) {
    return null;
  }

  final Rect frame = division.frame;
  if (division.isHorizontal) {
    // Choose the taller half, so a dialog gets as much room as possible.
    final double above = frame.top;
    final double below = size.height - frame.bottom;
    return above >= below
        ? Offset(size.width / 2, above / 2)
        : Offset(size.width / 2, frame.bottom + below / 2);
  }

  final double before = frame.left;
  final double after = size.width - frame.right;
  return before >= after
      ? Offset(before / 2, size.height / 2)
      : Offset(frame.right + after / 2, size.height / 2);
}
