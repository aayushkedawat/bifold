import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';

/// **Downstream example B: a fold-aware two-pane layout.**
///
/// Must behave sensibly on a book foldable, a flip foldable, an ordinary
/// phone, a tablet and desktop — again with no platform checks.
///
/// Almost all the work is [BifoldSplit], which aligns to the fold when there
/// is one and stacks when there is not. The only decision left to the app is
/// what "no fold, but plenty of room" should look like, which is a size class
/// question rather than a fold question.
class TwoPane extends StatelessWidget {
  /// Creates a two-pane layout.
  const TwoPane({required this.start, required this.end, super.key});

  /// The leading pane: the list, the index, the table of contents.
  final Widget start;

  /// The trailing pane: the detail.
  final Widget end;

  @override
  Widget build(BuildContext context) {
    final FoldInfo now = Bifold.of(context);

    return BifoldSplit(
      // With a fold, align to it. Without one, a roomy window still deserves
      // two panes and a cramped one does not.
      fallback: now.isRegular
          ? BifoldSplitFallback.sideBySide
          : BifoldSplitFallback.stack,
      start: start,
      end: end,
    );
  }
}
