import 'package:bifold/bifold.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The view size every test in this file lays out against.
const Size kViewSize = Size(800, 1000);

void main() {
  /// Pumps a [BifoldSplit] filling a view of [kViewSize] under [info].
  Future<void> pumpSplit(
    WidgetTester tester, {
    required FoldInfo info,
    BifoldSplitFallback fallback = BifoldSplitFallback.stack,
  }) async {
    tester.view
      ..physicalSize = kViewSize
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: BifoldScope.fake(
          info: info,
          child: BifoldSplit(
            fallback: fallback,
            start: const _Pane('start'),
            end: const _Pane('end'),
          ),
        ),
      ),
    );
    // One extra pump: the split measures its own offset from the view after
    // the first layout pass.
    await tester.pump();
  }

  Rect rectOf(WidgetTester tester, String label) =>
      tester.getRect(find.byKey(ValueKey<String>(label)));

  group('splitting across an active division', () {
    testWidgets('places the panes clear of the crease and its margins',
        (tester) async {
      await pumpSplit(
        tester,
        info: FoldInfoFakes.partiallyOpen(viewSize: kViewSize, thickness: 24),
      );

      final start = rectOf(tester, 'start');
      final end = rectOf(tester, 'end');

      // Crease spans 488..512, margins add 12 either side: avoid 476..524.
      expect(start.top, 0);
      expect(start.bottom, 476);
      expect(end.top, 524);
      expect(end.bottom, 1000);

      // Both panes keep the full width of a horizontal split.
      expect(start.width, kViewSize.width);
      expect(end.width, kViewSize.width);

      // Nothing is drawn in the crease itself.
      expect(start.bottom, lessThan(end.top));
    });

    testWidgets('splits vertically when the division runs top to bottom',
        (tester) async {
      await pumpSplit(
        tester,
        info: FoldInfoFakes.partiallyOpenVertical(
          viewSize: kViewSize,
          thickness: 24,
        ),
      );

      final start = rectOf(tester, 'start');
      final end = rectOf(tester, 'end');

      expect(start.left, 0);
      expect(start.right, 376);
      expect(end.left, 424);
      expect(end.right, 800);
      expect(start.height, kViewSize.height);
    });

    testWidgets('splits across a zero-thickness crease using its margins',
        (tester) async {
      // The display can crease without a gap. The margins still describe
      // clearance, so the panes must respect them.
      await pumpSplit(
        tester,
        info: FoldInfoFakes.partiallyOpen(viewSize: kViewSize, thickness: 0),
      );

      final start = rectOf(tester, 'start');
      final end = rectOf(tester, 'end');
      expect(start.bottom, 488);
      expect(end.top, 512);
    });
  });

  group('falling back when there is nothing to split across', () {
    testWidgets('stacks when the device is flat', (tester) async {
      // A flat display still reports a division, but an inactive one. A layout
      // that splits here has confused presence with activity.
      await pumpSplit(
        tester,
        info: FoldInfoFakes.fullyOpen(viewSize: kViewSize),
      );

      final start = rectOf(tester, 'start');
      final end = rectOf(tester, 'end');
      expect(start.height, 500);
      expect(end.top, 500);
    });

    testWidgets('stacks when the device is shut', (tester) async {
      await pumpSplit(tester, info: FoldInfoFakes.closed);
      expect(rectOf(tester, 'start').height, 500);
    });

    testWidgets('stacks on a device with no fold at all', (tester) async {
      await pumpSplit(tester, info: FoldInfo.unsupported);

      final start = rectOf(tester, 'start');
      final end = rectOf(tester, 'end');
      expect(start.height, 500);
      expect(end.height, 500);
    });

    testWidgets('sideBySide splits the width evenly', (tester) async {
      await pumpSplit(
        tester,
        info: FoldInfoFakes.fullyOpen(viewSize: kViewSize),
        fallback: BifoldSplitFallback.sideBySide,
      );

      expect(rectOf(tester, 'start').width, 400);
      expect(rectOf(tester, 'end').left, 400);
    });

    testWidgets('startOnly drops the second pane', (tester) async {
      await pumpSplit(
        tester,
        info: FoldInfoFakes.closed,
        fallback: BifoldSplitFallback.startOnly,
      );

      expect(find.byKey(const ValueKey<String>('start')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('end')), findsNothing);
    });

    testWidgets('ignores an occlusion, which does not separate the display',
        (tester) async {
      // An active camera cutout is something to avoid, not a reason to split.
      await pumpSplit(
        tester,
        info: FoldInfoFakes.fullyOpen(viewSize: kViewSize, cameraActive: true),
      );
      expect(rectOf(tester, 'start').height, 500);
    });
  });

  group('robustness', () {
    testWidgets('survives every pose in the matrix', (tester) async {
      for (final entry in FoldInfoFakes.poseMatrix(kViewSize).entries) {
        await pumpSplit(tester, info: entry.value);
        expect(
          tester.takeException(),
          isNull,
          reason: 'threw while laid out as ${entry.key}',
        );
        expect(
          find.byKey(const ValueKey<String>('start')),
          findsOneWidget,
          reason: 'start pane missing while laid out as ${entry.key}',
        );
      }
    });

    testWidgets('relayouts when the pose changes', (tester) async {
      tester.view
        ..physicalSize = kViewSize
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Widget build(FoldInfo info) => Directionality(
        textDirection: TextDirection.ltr,
        child: BifoldScope.fake(
          info: info,
          child: const BifoldSplit(
            start: _Pane('start'),
            end: _Pane('end'),
          ),
        ),
      );

      await tester.pumpWidget(build(FoldInfoFakes.closed));
      await tester.pump();
      expect(rectOf(tester, 'start').height, 500);

      await tester.pumpWidget(
        build(FoldInfoFakes.partiallyOpen(viewSize: kViewSize)),
      );
      await tester.pump();
      expect(rectOf(tester, 'start').bottom, 476);

      await tester.pumpWidget(build(FoldInfoFakes.closed));
      await tester.pump();
      expect(rectOf(tester, 'start').height, 500);
    });

    testWidgets('falls back inside an unbounded parent', (tester) async {
      // A split in a scroll view has no height to divide. It must degrade
      // rather than assert.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BifoldScope.fake(
            info: FoldInfoFakes.partiallyOpen(viewSize: kViewSize),
            child: ListView(
              children: const <Widget>[
                SizedBox(
                  height: 300,
                  child: BifoldSplit(
                    start: _Pane('start'),
                    end: _Pane('end'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey<String>('start')), findsOneWidget);
    });

    testWidgets('falls back when the division misses this widget entirely',
        (tester) async {
      // The crease is reported for the view at y=488..512, but this split only
      // occupies the bottom 200 logical pixels, so there is nothing to divide.
      tester.view
        ..physicalSize = kViewSize
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BifoldScope.fake(
            info: FoldInfoFakes.partiallyOpen(viewSize: kViewSize),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 200,
                width: 800,
                child: BifoldSplit(
                  start: const _Pane('start'),
                  end: const _Pane('end'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Stacked, not split: each pane gets half of the 200.
      expect(rectOf(tester, 'start').height, 100);
    });
  });
}

class _Pane extends StatelessWidget {
  const _Pane(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      SizedBox.expand(key: ValueKey<String>(label));
}
