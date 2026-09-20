import 'package:bifold/bifold.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const Size kViewSize = Size(800, 1000);

void main() {
  Future<void> pumpOverlay(
    WidgetTester tester, {
    required FoldInfo info,
    bool enabled = true,
    bool showLabels = true,
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
          child: BifoldDebugOverlay(
            enabled: enabled,
            showLabels: showLabels,
            child: const SizedBox.expand(
              key: ValueKey<String>('app'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the app underneath it', (tester) async {
    await pumpOverlay(
      tester,
      info: FoldInfoFakes.partiallyOpen(viewSize: kViewSize),
    );

    expect(find.byKey(const ValueKey<String>('app')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returns the child untouched when disabled', (tester) async {
    await pumpOverlay(
      tester,
      info: FoldInfoFakes.partiallyOpen(viewSize: kViewSize),
      enabled: false,
    );

    // No painter, and no Stack wrapping: the tree shape must not change.
    expect(find.byType(CustomPaint), findsNothing);
    expect(find.byKey(const ValueKey<String>('app')), findsOneWidget);
  });

  testWidgets('does not intercept pointer events', (tester) async {
    var taps = 0;

    tester.view
      ..physicalSize = kViewSize
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: BifoldScope.fake(
          info: FoldInfoFakes.partiallyOpen(viewSize: kViewSize),
          child: BifoldDebugOverlay(
            child: GestureDetector(
              // An empty SizedBox does not hit-test itself, so the detector
              // has to claim the area for the tap to have any target at all.
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Tap directly over the crease, where the overlay paints.
    await tester.tapAt(const Offset(400, 500));
    expect(taps, 1, reason: 'the overlay swallowed a tap on the app beneath');
  });

  testWidgets('paints without throwing for every pose', (tester) async {
    for (final entry in FoldInfoFakes.poseMatrix(kViewSize).entries) {
      await pumpOverlay(tester, info: entry.value);
      expect(
        tester.takeException(),
        isNull,
        reason: 'threw while painting ${entry.key}',
      );
    }
  });

  testWidgets('paints without labels when asked', (tester) async {
    await pumpOverlay(
      tester,
      info: FoldInfoFakes.partiallyOpen(viewSize: kViewSize),
      showLabels: false,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles a region larger than the view', (tester) async {
    // Defensive: a region reported for a view larger than this widget must
    // clamp rather than paint a label off-screen.
    await pumpOverlay(
      tester,
      info: const FoldInfo(
        isFoldable: true,
        display: FoldDisplay.inner,
        pose: FoldPose.partiallyOpen,
        regions: <FoldRegion>[
          FoldRegion(
            kind: RegionKind.division,
            frame: Rect.fromLTRB(-100, 4000, 5000, 4020),
            margins: EdgeInsets.zero,
            isActive: true,
          ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
