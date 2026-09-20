import 'package:bifold/bifold.dart';
import 'package:bifold/src/anchoring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Size kViewSize = Size(800, 1000);

void main() {
  group('bifoldAnchorPointFor', () {
    test('returns null when there is nothing to avoid', () {
      // Passing this straight to showDialog must be safe, and null is what
      // showDialog expects for its default behaviour.
      expect(bifoldAnchorPointFor(FoldInfo.unsupported, kViewSize), isNull);
      expect(bifoldAnchorPointFor(FoldInfoFakes.closed, kViewSize), isNull);
      expect(
        bifoldAnchorPointFor(
          FoldInfoFakes.fullyOpen(viewSize: kViewSize),
          kViewSize,
        ),
        isNull,
      );
    });

    test('anchors into a half, never onto the crease', () {
      final info = FoldInfoFakes.partiallyOpen(viewSize: kViewSize);
      final point = bifoldAnchorPointFor(info, kViewSize)!;
      final crease = info.division!.frame;

      expect(
        point.dy < crease.top || point.dy > crease.bottom,
        isTrue,
        reason: 'anchor landed on the crease at $point',
      );
    });

    test('picks the taller half', () {
      // Crease high up: the space below is larger, so the dialog goes below.
      const info = FoldInfo(
        isFoldable: true,
        display: FoldDisplay.inner,
        pose: FoldPose.partiallyOpen,
        regions: <FoldRegion>[
          FoldRegion(
            kind: RegionKind.division,
            frame: Rect.fromLTRB(0, 200, 800, 240),
            margins: EdgeInsets.zero,
            isActive: true,
          ),
        ],
      );

      final point = bifoldAnchorPointFor(info, kViewSize)!;
      expect(point.dy, greaterThan(240));
    });

    test('handles a vertical crease by picking the wider half', () {
      final info = FoldInfoFakes.partiallyOpenVertical(viewSize: kViewSize);
      final point = bifoldAnchorPointFor(info, kViewSize)!;
      final crease = info.division!.frame;

      expect(
        point.dx < crease.left || point.dx > crease.right,
        isTrue,
        reason: 'anchor landed on the crease at $point',
      );
    });
  });

  group('bifoldAnchorPoint', () {
    testWidgets('reads from the scope', (tester) async {
      tester.view
        ..physicalSize = kViewSize
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Offset? seen;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: kViewSize),
          child: BifoldScope.fake(
            info: FoldInfoFakes.partiallyOpen(viewSize: kViewSize),
            child: Builder(
              builder: (context) {
                seen = bifoldAnchorPoint(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(seen, isNotNull);
    });

    testWidgets('returns null with no scope, so it stays safe to pass',
        (tester) async {
      Offset? seen = Offset.zero;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: kViewSize),
          child: Builder(
            builder: (context) {
              seen = bifoldAnchorPoint(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(seen, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('BifoldGrid', () {
    testWidgets('lays out in every pose without throwing', (tester) async {
      tester.view
        ..physicalSize = kViewSize
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final entry in FoldInfoFakes.poseMatrix(kViewSize).entries) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: BifoldScope.fake(
              info: entry.value,
              child: BifoldGrid(
                tileExtent: 150,
                children: List<Widget>.generate(
                  20,
                  (i) => ColoredBox(
                    key: ValueKey<int>(i),
                    color: const Color(0xFF222222),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'threw while laid out as ${entry.key}',
        );
      }
    });

    testWidgets('never draws a tile across an active crease', (tester) async {
      tester.view
        ..physicalSize = kViewSize
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final info = FoldInfoFakes.partiallyOpen(viewSize: kViewSize);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BifoldScope.fake(
            info: info,
            child: BifoldGrid(
              tileExtent: 150,
              children: List<Widget>.generate(
                20,
                (i) => ColoredBox(
                  key: ValueKey<int>(i),
                  color: const Color(0xFF222222),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final crease = info.division!.frame;
      for (var i = 0; i < 20; i++) {
        final finder = find.byKey(ValueKey<int>(i));
        if (!tester.any(finder)) continue;
        final rect = tester.getRect(finder);
        if (rect.isEmpty) continue;
        final overlaps = rect.top < crease.bottom && rect.bottom > crease.top;
        expect(
          overlaps,
          isFalse,
          reason: 'tile $i at $rect straddles the crease $crease',
        );
      }
    });
  });
}
