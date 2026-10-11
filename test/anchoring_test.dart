import 'dart:math' as math;

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

    // A crease runs one of two ways: across the display, splitting it into a
    // top and a bottom part, or down it, splitting it into a left and a right
    // one. Only the first was ever handled here, which let a book-style fold —
    // the shape most foldables actually are — draw every tile straight through
    // the hinge while this widget's own documentation said it never would.
    final List<FoldInfo> creases = <FoldInfo>[
      FoldInfoFakes.partiallyOpen(viewSize: kViewSize),
      FoldInfoFakes.partiallyOpenVertical(viewSize: kViewSize),
    ];

    testWidgets('never draws a tile across an active crease', (tester) async {
      for (final info in creases) {
        await _pumpGrid(tester, info);

        final FoldRegion division = info.division!;
        final Rect crease = division.frame;
        final bool splitsRows = division.isHorizontal;
        var before = 0;
        var after = 0;

        for (var i = 0; i < 20; i++) {
          final finder = find.byKey(ValueKey<int>(i));
          if (!tester.any(finder)) continue;
          final rect = tester.getRect(finder);
          if (rect.isEmpty) continue;

          final bool overlaps = splitsRows
              ? rect.top < crease.bottom && rect.bottom > crease.top
              : rect.left < crease.right && rect.right > crease.left;
          expect(
            overlaps,
            isFalse,
            reason: 'tile $i at $rect straddles the crease $crease',
          );

          if (splitsRows) {
            before += rect.bottom <= crease.top ? 1 : 0;
            after += rect.top >= crease.bottom ? 1 : 0;
          } else {
            before += rect.right <= crease.left ? 1 : 0;
            after += rect.left >= crease.right ? 1 : 0;
          }
        }

        expect(
          before,
          greaterThan(0),
          reason: 'nothing was laid out before the crease $crease, so the '
              'tiles were not split at all — straddling one side is only '
              'half a fix',
        );
        expect(after, greaterThan(0), reason: 'nothing landed past $crease');
      }
    });

    testWidgets('gives each side of a vertical crease its own column count', (
      tester,
    ) async {
      // Both sides are 376 wide against a 150 target, so two columns each. A
      // count taken from the full 800 would put five narrow ones on the left
      // and overflow it into the hinge.
      final info = FoldInfoFakes.partiallyOpenVertical(viewSize: kViewSize);
      await _pumpGrid(tester, info);

      final Rect crease = info.division!.frame;
      final Rect first = tester.getRect(find.byKey(const ValueKey<int>(0)));
      final Rect second = tester.getRect(find.byKey(const ValueKey<int>(1)));
      final Rect third = tester.getRect(find.byKey(const ValueKey<int>(2)));

      expect(first.left, 0);
      expect(second.left, greaterThan(first.right));
      expect(
        first.width,
        closeTo((crease.left - 8) / 2, 0.01),
        reason: 'the left pane sized its tiles for the whole display',
      );
      expect(third.left, first.left, reason: 'the third tile starts row two');
    });

    testWidgets('starts every pane at the top of the box', (tester) async {
      // A Row centres its children by default, and the near pane is a
      // fixed-width box around a shrink-wrapped grid, so left to centre it
      // floats to the middle of whatever the far pane measures. Measured 24
      // logical pixels below the far pane's first tile with twenty tiles, and
      // 312 — a third of the way down the display — with three. Tiles stop at
      // the crease either way, so the straddle checks above are blind to it.
      for (final count in <int>[20, 3]) {
        final info = FoldInfoFakes.partiallyOpenVertical(viewSize: kViewSize);
        await _pumpGrid(tester, info, count: count);

        final Rect crease = info.division!.frame;
        final List<double> near = <double>[];
        final List<double> far = <double>[];
        for (var i = 0; i < count; i++) {
          final finder = find.byKey(ValueKey<int>(i));
          if (!tester.any(finder)) continue;
          final rect = tester.getRect(finder);
          if (rect.right <= crease.left) {
            near.add(rect.top);
          } else if (rect.left >= crease.right) {
            far.add(rect.top);
          }
        }

        expect(near, isNotEmpty, reason: 'nothing in the near pane');
        expect(
          near.reduce(math.min),
          0.0,
          reason: 'the near pane does not start at the top with $count tiles',
        );
        if (far.isNotEmpty) {
          expect(
            far.reduce(math.min),
            0.0,
            reason: 'the far pane does not start at the top with $count tiles',
          );
        }
      }
    });
  });
}

Future<void> _pumpGrid(WidgetTester tester, FoldInfo info,
    {int count = 20}) async {
  tester.view
    ..physicalSize = kViewSize
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: BifoldScope.fake(
        info: info,
        child: BifoldGrid(
          tileExtent: 150,
          children: List<Widget>.generate(
            count,
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
}
