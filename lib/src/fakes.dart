import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/painting.dart' show EdgeInsets;

import 'bifold_platform_interface.dart';
import 'capabilities.dart';
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
  }) =>
      FoldInfo(
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
  }) =>
      FoldInfo(
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

/// Ready-made [BifoldCapabilities] for tests and previews.
///
/// Named after device *shapes*, never after products: a profile models what a
/// class of hardware can do, and pinning a brand name to it would promise a
/// fidelity these values do not have.
abstract final class BifoldCapabilityFakes {
  static CapabilityEvidence _yes(String source) =>
      CapabilityEvidence(status: CapabilityStatus.supported, source: source);

  static CapabilityEvidence _no(String source) =>
      CapabilityEvidence(status: CapabilityStatus.unsupported, source: source);

  static const CapabilityEvidence _dunno = CapabilityEvidence.unknown;

  static BifoldCapabilities _build({
    required Map<FoldFeature, CapabilityEvidence> evidence,
    required FoldFormFactor formFactor,
    Set<RearDisplayMode> rearDisplayModes = const <RearDisplayMode>{},
  }) =>
      BifoldCapabilities(
        evidence: Map<FoldFeature,
            CapabilityEvidence>.unmodifiable(<FoldFeature, CapabilityEvidence>{
          for (final FoldFeature feature in FoldFeature.values)
            feature: evidence[feature] ?? _dunno,
        }),
        formFactor: formFactor,
        rearDisplayModes: Set<RearDisplayMode>.unmodifiable(rearDisplayModes),
        isResolved: true,
      );

  /// A device with no fold of any kind.
  ///
  /// The same value as [BifoldCapabilities.none], named for symmetry with the
  /// other profiles so a capability matrix reads consistently.
  static const BifoldCapabilities flat = BifoldCapabilities.none;

  /// A book-style foldable: a vertical hinge opening into a larger display.
  static BifoldCapabilities book({bool rearDisplay = false}) => _build(
        formFactor: FoldFormFactor.book,
        rearDisplayModes: rearDisplay
            ? const <RearDisplayMode>{RearDisplayMode.presentation}
            : const <RearDisplayMode>{},
        evidence: <FoldFeature, CapabilityEvidence>{
          FoldFeature.fold: _yes('fake.book'),
          FoldFeature.hingeAngle: _yes('fake.book'),
          FoldFeature.halfOpenedPosture: _yes('fake.book'),
          FoldFeature.reservedRegions: _yes('fake.book'),
          FoldFeature.separatingFold: _yes('fake.book'),
          FoldFeature.foldOcclusion: _no('fake.book'),
          FoldFeature.coverDisplay: _yes('fake.book'),
          FoldFeature.rearDisplay:
              rearDisplay ? _yes('fake.book') : _no('fake.book'),
        },
      );

  /// A flip-style foldable: a horizontal hinge closing into a smaller square.
  static BifoldCapabilities flip() => _build(
        formFactor: FoldFormFactor.flip,
        evidence: <FoldFeature, CapabilityEvidence>{
          FoldFeature.fold: _yes('fake.flip'),
          FoldFeature.hingeAngle: _yes('fake.flip'),
          FoldFeature.halfOpenedPosture: _yes('fake.flip'),
          FoldFeature.reservedRegions: _yes('fake.flip'),
          FoldFeature.separatingFold: _yes('fake.flip'),
          FoldFeature.foldOcclusion: _no('fake.flip'),
          FoldFeature.coverDisplay: _yes('fake.flip'),
          FoldFeature.rearDisplay: _no('fake.flip'),
        },
      );

  /// A foldable seen only while shut, so almost nothing is established.
  ///
  /// The case that catches code treating a false `hasX` as a proven "no":
  /// [BifoldCapabilities.hasFold] is true from a static signal, while the
  /// posture capability is still [CapabilityStatus.unknown] because nothing
  /// has been observed.
  static BifoldCapabilities unopenedFoldable() => _build(
        formFactor: FoldFormFactor.unknown,
        evidence: <FoldFeature, CapabilityEvidence>{
          FoldFeature.fold: _yes('fake.static_device_feature'),
          FoldFeature.hingeAngle: _yes('fake.static_device_feature'),
        },
      );

  /// Nothing established at all.
  static const BifoldCapabilities unresolved = BifoldCapabilities.unresolved;

  /// The capabilities a given fold state would require to be possible.
  ///
  /// Lets `BifoldScope.fake` accept a [FoldInfo] alone and still supply
  /// coherent capabilities, so a test exercising layout does not have to
  /// restate what the device can do. Observation only ever adds: a state that
  /// shows no fold yields [BifoldCapabilities.unresolved] rather than a claim
  /// that the device cannot fold.
  static BifoldCapabilities impliedBy(FoldInfo info) {
    if (!info.isFoldable) {
      return info.isResolved
          ? BifoldCapabilities.none
          : BifoldCapabilities.unresolved;
    }
    final Map<FoldFeature, CapabilityEvidence> evidence =
        <FoldFeature, CapabilityEvidence>{
      FoldFeature.fold: _yes('fake.implied_by_state'),
      if (info.hingeAngle != null)
        FoldFeature.hingeAngle: _yes('fake.implied_by_state'),
      if (info.pose == FoldPose.partiallyOpen)
        FoldFeature.halfOpenedPosture: _yes('fake.implied_by_state'),
      if (info.regions.isNotEmpty)
        FoldFeature.reservedRegions: _yes('fake.implied_by_state'),
      if (info.display == FoldDisplay.outer)
        FoldFeature.coverDisplay: _yes('fake.implied_by_state'),
    };
    return _build(evidence: evidence, formFactor: FoldFormFactor.unknown);
  }
}

/// A [BifoldPlatform] whose fold state and capabilities a test drives by hand.
///
/// `BifoldScope.fake` covers a fixed state, and pumping a new one covers a
/// transition. This covers what neither can: the *stream* itself — ordering,
/// late arrivals, a capability resolving after the first frame.
///
/// ```dart
/// final platform = FakeBifoldPlatform();
/// BifoldPlatform.instance = platform;
/// addTearDown(platform.dispose);
///
/// await tester.pumpWidget(const BifoldScope(child: MyApp()));
/// platform.emit(FoldInfoFakes.partiallyOpen(viewSize: size));
/// await tester.pump();
/// ```
class FakeBifoldPlatform extends BifoldPlatform {
  /// Creates a fake platform reporting [initial] until told otherwise.
  FakeBifoldPlatform({
    FoldInfo initial = FoldInfo.unsupported,
    BifoldCapabilities capabilities = BifoldCapabilities.unresolved,
  })  : _info = initial,
        _capabilities = capabilities;

  final StreamController<FoldInfo> _foldEvents =
      StreamController<FoldInfo>.broadcast();
  final StreamController<BifoldCapabilities> _capabilityEvents =
      StreamController<BifoldCapabilities>.broadcast();

  FoldInfo _info;
  BifoldCapabilities _capabilities;

  /// Pushes a new fold state to every listener.
  void emit(FoldInfo info) {
    _info = info;
    _foldEvents.add(info);
  }

  /// Pushes new capabilities to every listener.
  void emitCapabilities(BifoldCapabilities capabilities) {
    _capabilities = capabilities;
    _capabilityEvents.add(capabilities);
  }

  /// Closes both streams. Call from `addTearDown`.
  Future<void> dispose() async {
    await _foldEvents.close();
    await _capabilityEvents.close();
  }

  @override
  Future<FoldInfo> getFoldInfo() async => _info;

  @override
  Stream<FoldInfo> foldInfoStream() => _foldEvents.stream;

  @override
  Future<BifoldCapabilities> getCapabilities() async => _capabilities;

  @override
  Stream<BifoldCapabilities> capabilitiesStream() => _capabilityEvents.stream;

  @override
  Future<String?> debugDescribeNativeApi() async => 'FakeBifoldPlatform';
}
