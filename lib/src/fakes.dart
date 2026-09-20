import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/painting.dart' show EdgeInsets;

import 'models.dart';

/// Ready-made [FoldInfo] values for tests and previews.
///
/// These let a fold-aware layout be tested on any machine, with no simulator,
/// no iOS SDK and no channel mocking. Pair them with `BifoldScope.fake`:
///
/// ```dart
/// await tester.pumpWidget(
///   BifoldScope.fake(
///     info: FoldInfoFakes.partiallyOpen(viewSize: const Size(800, 1000)),
///     child: const MyReader(),
///   ),
/// );
/// ```
///
/// The geometry these produce is *synthetic*. It is shaped to match how the
/// platform reports regions — a division spanning the full width of the view,
/// an occlusion near the top edge — but the numbers are not measured from
/// hardware and must not be used as a reference for real device dimensions.
/// They exist to exercise layout logic, not to model a specific device.
abstract final class FoldInfoFakes {
  /// Clearance the fakes report inside a division's frame, in logical pixels.
  ///
  /// An arbitrary but non-zero value, chosen so that tests which confuse the
  /// frame with the hardware rect visibly differ from tests which do not.
  ///
  /// Like the platform, the fakes report a `frame` that *already contains*
  /// this clearance; [FoldRegion.reservedRect] is the bare crease inside it.
  static const double divisionMargin = 12.0;

  /// A non-foldable device.
  ///
  /// Identical to [FoldInfo.unsupported], named for symmetry with the other
  /// fakes so a pose matrix reads consistently.
  static const FoldInfo unsupported = FoldInfo.unsupported;

  /// A foldable that is shut, showing the outer display.
  ///
  /// Reports no regions at all, which is what the platform does on the outer
  /// display.
  static const FoldInfo closed = FoldInfo(
    isFoldable: true,
    display: FoldDisplay.outer,
    pose: FoldPose.closed,
    regions: <FoldRegion>[],
    hingeAngle: 0,
  );

  /// A foldable open flat on its inner display.
  ///
  /// The division is reported but **inactive**, because a flat display has no
  /// crease to avoid. This is the case that catches layouts which split on the
  /// presence of a division rather than on its [FoldRegion.isActive] flag.
  static FoldInfo fullyOpen({
    required Size viewSize,
    bool cameraActive = false,
  }) => FoldInfo(
    isFoldable: true,
    display: FoldDisplay.inner,
    pose: FoldPose.fullyOpen,
    regions: List<FoldRegion>.unmodifiable(<FoldRegion>[
      _division(viewSize, isActive: false),
      _occlusion(viewSize, isActive: cameraActive),
    ]),
    hingeAngle: math.pi,
  );

  /// A foldable part-way open, so the inner display is creased.
  ///
  /// This is the only pose that reports an active division, and the one a
  /// two-pane layout should react to.
  ///
  /// [thickness] is the height of the bare crease in logical pixels, not
  /// counting [divisionMargin] either side. Pass zero to model a crease with no
  /// measurable width, which the platform can report: the region still marks
  /// where the display bends.
  static FoldInfo partiallyOpen({
    required Size viewSize,
    double thickness = 24.0,
    bool cameraActive = false,
    double hingeAngle = math.pi / 2,
  }) => FoldInfo(
    isFoldable: true,
    display: FoldDisplay.inner,
    pose: FoldPose.partiallyOpen,
    regions: List<FoldRegion>.unmodifiable(<FoldRegion>[
      _division(viewSize, isActive: true, thickness: thickness),
      _occlusion(viewSize, isActive: cameraActive),
    ]),
    hingeAngle: hingeAngle,
  );

  /// A foldable whose division runs top-to-bottom rather than side-to-side.
  ///
  /// The inner display does not honour supported interface orientations, so a
  /// layout can be handed either axis. Test both.
  static FoldInfo partiallyOpenVertical({
    required Size viewSize,
    double thickness = 24.0,
  }) {
    final double centre = viewSize.width / 2;
    // The frame spans the crease plus its clearance, matching how the platform
    // reports it.
    final double half = (thickness / 2) + divisionMargin;
    return FoldInfo(
      isFoldable: true,
      display: FoldDisplay.inner,
      pose: FoldPose.partiallyOpen,
      regions: List<FoldRegion>.unmodifiable(<FoldRegion>[
        FoldRegion(
          kind: RegionKind.division,
          frame: Rect.fromLTRB(
            centre - half,
            0,
            centre + half,
            viewSize.height,
          ),
          margins: const EdgeInsets.symmetric(horizontal: divisionMargin),
          isActive: true,
        ),
      ]),
      hingeAngle: math.pi / 2,
    );
  }

  /// Every pose, for driving a table-based test.
  ///
  /// ```dart
  /// for (final entry in FoldInfoFakes.poseMatrix(size).entries) {
  ///   testWidgets('reader lays out when ${entry.key}', (tester) async {
  ///     await tester.pumpWidget(
  ///       BifoldScope.fake(info: entry.value, child: const Reader()),
  ///     );
  ///     expect(tester.takeException(), isNull);
  ///   });
  /// }
  /// ```
  static Map<String, FoldInfo> poseMatrix(Size viewSize) => <String, FoldInfo>{
    'unsupported': unsupported,
    'closed': closed,
    'fullyOpen': fullyOpen(viewSize: viewSize),
    'partiallyOpen': partiallyOpen(viewSize: viewSize),
    'partiallyOpen (zero-thickness crease)': partiallyOpen(
      viewSize: viewSize,
      thickness: 0,
    ),
    'partiallyOpen (vertical)': partiallyOpenVertical(viewSize: viewSize),
    'partiallyOpen (camera active)': partiallyOpen(
      viewSize: viewSize,
      cameraActive: true,
    ),
  };

  static FoldRegion _division(
    Size viewSize, {
    required bool isActive,
    double thickness = 24.0,
  }) {
    final double centre = viewSize.height / 2;
    // The frame spans the crease plus its clearance, matching how the platform
    // reports it.
    final double half = (thickness / 2) + divisionMargin;
    return FoldRegion(
      kind: RegionKind.division,
      frame: Rect.fromLTRB(
        0,
        centre - half,
        viewSize.width,
        centre + half,
      ),
      margins: const EdgeInsets.symmetric(vertical: divisionMargin),
      isActive: isActive,
    );
  }

  static FoldRegion _occlusion(Size viewSize, {required bool isActive}) =>
      FoldRegion(
        kind: RegionKind.occlusion,
        frame: Rect.fromLTWH((viewSize.width / 2) - 20, 0, 40, 40),
        margins: EdgeInsets.zero,
        isActive: isActive,
      );
}
