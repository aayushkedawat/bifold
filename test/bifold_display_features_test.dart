import 'dart:ui' as ui;

import 'package:bifold/bifold.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const Size kViewSize = Size(800, 1000);

void main() {
  group('toDisplayFeatures', () {
    test('maps an active division to a fold, not a hinge', () {
      // The inner display is continuous with no physical gap, so `fold` is
      // correct and `hinge` would be wrong. This matches flutter/flutter#193025.
      final features = BifoldDisplayFeatures.toDisplayFeatures(
        FoldInfoFakes.partiallyOpen(viewSize: kViewSize),
      );

      final fold = features.firstWhere(
        (f) => f.type == ui.DisplayFeatureType.fold,
      );
      expect(fold.state, ui.DisplayFeatureState.postureHalfOpened);
      expect(fold.bounds.width, kViewSize.width);
    });

    test('drops inactive regions', () {
      // A flat display still reports a division, but an inactive one is not
      // something that is actually there.
      final features = BifoldDisplayFeatures.toDisplayFeatures(
        FoldInfoFakes.fullyOpen(viewSize: kViewSize),
      );
      expect(features, isEmpty);
    });

    test('maps an active occlusion to a cutout with unknown state', () {
      // dart:ui asserts that a cutout's state is unknown.
      final features = BifoldDisplayFeatures.toDisplayFeatures(
        FoldInfoFakes.partiallyOpen(
          viewSize: kViewSize,
          cameraActive: true,
        ),
      );

      final cutout = features.firstWhere(
        (f) => f.type == ui.DisplayFeatureType.cutout,
      );
      expect(cutout.state, ui.DisplayFeatureState.unknown);
    });

    test('reports nothing while shut', () {
      // dart:ui has no closed posture.
      expect(
        BifoldDisplayFeatures.toDisplayFeatures(FoldInfoFakes.closed),
        isEmpty,
      );
    });

    test('reports nothing on a device with no fold', () {
      expect(
        BifoldDisplayFeatures.toDisplayFeatures(FoldInfo.unsupported),
        isEmpty,
      );
    });

    test('drops a region kind it does not recognise', () {
      // Calling an unknown kind a fold would make layouts split across it.
      const info = FoldInfo(
        isFoldable: true,
        display: FoldDisplay.inner,
        pose: FoldPose.partiallyOpen,
        regions: <FoldRegion>[
          FoldRegion(
            kind: RegionKind.unknown,
            frame: Rect.fromLTRB(0, 490, 800, 510),
            margins: EdgeInsets.zero,
            isActive: true,
          ),
        ],
      );
      expect(BifoldDisplayFeatures.toDisplayFeatures(info), isEmpty);
    });

    test('drops a zero-area region', () {
      const info = FoldInfo(
        isFoldable: true,
        display: FoldDisplay.inner,
        pose: FoldPose.partiallyOpen,
        regions: <FoldRegion>[
          FoldRegion(
            kind: RegionKind.division,
            frame: Rect.fromLTRB(0, 500, 800, 500),
            margins: EdgeInsets.zero,
            isActive: true,
          ),
        ],
      );
      expect(BifoldDisplayFeatures.toDisplayFeatures(info), isEmpty);
    });
  });

  group('BifoldDisplayFeatures widget', () {
    testWidgets('publishes features into MediaQuery', (tester) async {
      late MediaQueryData seen;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: kViewSize),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: BifoldScope.fake(
              info: FoldInfoFakes.partiallyOpen(viewSize: kViewSize),
              child: BifoldDisplayFeatures(
                child: Builder(
                  builder: (context) {
                    seen = MediaQuery.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(seen.displayFeatures, hasLength(1));
      expect(seen.displayFeatures.single.type, ui.DisplayFeatureType.fold);
    });

    testWidgets('steps aside once the engine reports its own features',
        (tester) async {
      // When flutter/flutter#193025 lands, the engine fills this in for real.
      // Two writers would be one too many, so the widget must not overwrite.
      const engineFeature = ui.DisplayFeature(
        bounds: Rect.fromLTRB(0, 100, 800, 120),
        type: ui.DisplayFeatureType.fold,
        state: ui.DisplayFeatureState.postureFlat,
      );
      late MediaQueryData seen;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: kViewSize,
            displayFeatures: <ui.DisplayFeature>[engineFeature],
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: BifoldScope.fake(
              info: FoldInfoFakes.partiallyOpen(viewSize: kViewSize),
              child: BifoldDisplayFeatures(
                child: Builder(
                  builder: (context) {
                    seen = MediaQuery.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(seen.displayFeatures, <ui.DisplayFeature>[engineFeature]);
    });

    testWidgets('leaves MediaQuery untouched when there is no fold',
        (tester) async {
      late MediaQueryData seen;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: kViewSize),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: BifoldScope.fake(
              info: FoldInfo.unsupported,
              child: BifoldDisplayFeatures(
                child: Builder(
                  builder: (context) {
                    seen = MediaQuery.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(seen.displayFeatures, isEmpty);
    });
  });
}
