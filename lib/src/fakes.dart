import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/painting.dart' show EdgeInsets;

import 'bifold_platform_interface.dart';
import 'capabilities.dart';
import 'models.dart';
import 'rear_display.dart';

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
    // The cover display behaves like a conventional phone.
    horizontalSizeClass: FoldSizeClass.compact,
    verticalSizeClass: FoldSizeClass.regular,
    isResolved: true,
  );

  /// A resolved non-foldable phone.
  ///
  /// The most common device in any app's install base, and the case
  /// [FoldInfo.unsupported] cannot stand in for: this one has *answered*.
  /// Use it to check that a layout settles on its no-fold branch rather than
  /// waiting forever for a platform that already replied.
  static const FoldInfo flat = FoldInfo(
    isFoldable: false,
    display: FoldDisplay.none,
    pose: FoldPose.unknown,
    regions: <FoldRegion>[],
    horizontalSizeClass: FoldSizeClass.compact,
    verticalSizeClass: FoldSizeClass.regular,
    isResolved: true,
  );

  /// A foldable whose hinge sensor is present but silent.
  ///
  /// `hasHingeAngle` is true while [FoldInfo.hingeAngle] is null, which is the
  /// state a sensor that never delivers produces. A hinge-reactive UI should
  /// fall back to [FoldInfo.pose] here rather than wait for a reading.
  static const FoldInfo silentHinge = FoldInfo(
    isFoldable: true,
    display: FoldDisplay.inner,
    pose: FoldPose.fullyOpen,
    regions: <FoldRegion>[],
    horizontalSizeClass: FoldSizeClass.regular,
    verticalSizeClass: FoldSizeClass.regular,
    isResolved: true,
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
        horizontalSizeClass: FoldSizeClass.regular,
        verticalSizeClass: FoldSizeClass.regular,
        verticalBarEdge: VerticalBarEdge.trailing,
        isResolved: true,
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
        horizontalSizeClass: FoldSizeClass.regular,
        verticalSizeClass: FoldSizeClass.regular,
        verticalBarEdge: VerticalBarEdge.trailing,
        isResolved: true,
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
      horizontalSizeClass: FoldSizeClass.regular,
      verticalSizeClass: FoldSizeClass.regular,
      isResolved: true,
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
        'unsupported (nothing has answered yet)': unsupported,
        'flat (resolved non-foldable)': flat,
        'closed': closed,
        'foldable with a silent hinge': silentHinge,
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

/// Ready-made [RearDisplayAvailability] values for tests and previews.
///
/// Covers the five situations a rear-display UI has to handle, which is one
/// more than [RearDisplayStatus] has values: "nothing has reported yet" is not
/// a status, it is the absence of one.
abstract final class RearDisplayFakes {
  /// Nothing has reported yet. A control should wait, not hide.
  static const RearDisplayAvailability unresolved =
      RearDisplayAvailability.unresolved;

  /// Settled: this device cannot present at all. Hide the control.
  static const RearDisplayAvailability unsupported =
      RearDisplayAvailability.none;

  /// Supported, but not right now — on iOS, no capture session is running.
  /// Disable the control rather than hiding it.
  static const RearDisplayAvailability unavailable = RearDisplayAvailability(
    presentation: RearDisplayStatus.unavailable,
    transfer: RearDisplayStatus.unsupported,
    isResolved: true,
  );

  /// Ready to start.
  static const RearDisplayAvailability available = RearDisplayAvailability(
    presentation: RearDisplayStatus.available,
    transfer: RearDisplayStatus.unsupported,
    isResolved: true,
  );

  /// A presentation session is running.
  static const RearDisplayAvailability presenting = RearDisplayAvailability(
    presentation: RearDisplayStatus.active,
    transfer: RearDisplayStatus.unsupported,
    isResolved: true,
  );

  /// Both modes offered, which only Android does.
  static const RearDisplayAvailability bothAvailable = RearDisplayAvailability(
    presentation: RearDisplayStatus.available,
    transfer: RearDisplayStatus.available,
    isResolved: true,
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

  /// Two physical displays with a gap between them.
  ///
  /// Shipped so a layout can be tested against the shape, even though no
  /// platform can currently report it: `FoldFormFactor.dualScreen` needs
  /// stronger evidence than a hinge orientation, which cannot tell one
  /// flexible display from two physical ones. The occlusion capability is
  /// `supported` here because a real gap genuinely hides content, which is
  /// what separates this shape from a crease.
  static BifoldCapabilities dualScreen() => _build(
        formFactor: FoldFormFactor.dualScreen,
        evidence: <FoldFeature, CapabilityEvidence>{
          FoldFeature.fold: _yes('fake.dual_screen'),
          FoldFeature.hingeAngle: _yes('fake.dual_screen'),
          FoldFeature.halfOpenedPosture: _yes('fake.dual_screen'),
          FoldFeature.reservedRegions: _yes('fake.dual_screen'),
          FoldFeature.separatingFold: _yes('fake.dual_screen'),
          FoldFeature.foldOcclusion: _yes('fake.dual_screen'),
          FoldFeature.coverDisplay: _no('fake.dual_screen'),
          FoldFeature.rearDisplay: _no('fake.dual_screen'),
        },
      );

  /// A book foldable that can move the whole app to its outer display.
  ///
  /// The only profile offering [RearDisplayMode.transfer], which has no iOS
  /// equivalent — so without this nothing exercises the Android-only path.
  static BifoldCapabilities bookWithTransfer() => _build(
        formFactor: FoldFormFactor.book,
        rearDisplayModes: const <RearDisplayMode>{
          RearDisplayMode.presentation,
          RearDisplayMode.transfer,
        },
        evidence: <FoldFeature, CapabilityEvidence>{
          FoldFeature.fold: _yes('fake.book_transfer'),
          FoldFeature.hingeAngle: _yes('fake.book_transfer'),
          FoldFeature.halfOpenedPosture: _yes('fake.book_transfer'),
          FoldFeature.reservedRegions: _yes('fake.book_transfer'),
          FoldFeature.separatingFold: _yes('fake.book_transfer'),
          FoldFeature.foldOcclusion: _no('fake.book_transfer'),
          FoldFeature.coverDisplay: _yes('fake.book_transfer'),
          FoldFeature.rearDisplay: _yes('fake.book_transfer'),
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
    RearDisplayAvailability rearDisplay = RearDisplayAvailability.unresolved,
  })  : _info = initial,
        _capabilities = capabilities,
        _rearDisplay = rearDisplay;

  final StreamController<FoldInfo> _foldEvents =
      StreamController<FoldInfo>.broadcast();
  final StreamController<BifoldCapabilities> _capabilityEvents =
      StreamController<BifoldCapabilities>.broadcast();
  final StreamController<RearDisplayAvailability> _rearDisplayEvents =
      StreamController<RearDisplayAvailability>.broadcast();

  FoldInfo _info;
  BifoldCapabilities _capabilities;
  RearDisplayAvailability _rearDisplay;

  int _foldStreamRequests = 0;

  /// How many times [foldInfoStream] has been asked for.
  ///
  /// Lets a test assert that several `BifoldScope`s each take the stream but
  /// that only one subscription exists behind them — which is the property
  /// `MethodChannelBifold` provides by memoising its stream, and the one worth
  /// locking in.
  int get foldStreamRequests => _foldStreamRequests;

  /// Whether anything is currently subscribed to the fold stream.
  ///
  /// A count of individual subscribers is deliberately not offered: a
  /// broadcast controller reports only its first listen and its last cancel,
  /// so any number derived from those callbacks would be wrong rather than
  /// merely coarse.
  bool get foldStreamIsSubscribed => _foldEvents.hasListener;

  Completer<FoldInfo>? _pendingRead;

  /// Makes the next [getFoldInfo] hang until [completePendingRead] is called.
  ///
  /// The seed query racing the stream is a real startup condition — a slow
  /// one-shot read must never overwrite newer stream state — and it cannot be
  /// reproduced without holding the read open.
  void holdNextRead() => _pendingRead ??= Completer<FoldInfo>();

  /// Releases a read held by [holdNextRead], answering with [info] or the
  /// current state.
  void completePendingRead([FoldInfo? info]) {
    final Completer<FoldInfo>? pending = _pendingRead;
    _pendingRead = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(info ?? _info);
    }
  }

  /// Pushes an error through the fold stream.
  ///
  /// A platform can fail mid-flight, and a scope has to survive it rather than
  /// tear down the subtree beneath it. Nothing else can produce that state.
  void emitError(Object error) => _foldEvents.addError(error);

  /// Pushes a new rear-display availability to every listener.
  void emitRearDisplay(RearDisplayAvailability availability) {
    _rearDisplay = availability;
    _rearDisplayEvents.add(availability);
  }

  /// What [presentOnRearDisplay] and [transferToRearDisplay] will answer.
  ///
  /// The system is allowed to refuse, and an app has to stay usable when it
  /// does, so a test needs to be able to make it refuse.
  bool rearDisplayRequestsSucceed = true;

  /// Every rear-display call made on this fake, in order.
  ///
  /// For asserting that a UI asked for what it said it would — `present`,
  /// `transfer` or `end` — without reaching a platform channel.
  final List<String> rearDisplayCalls = <String>[];

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

  /// Closes every stream. Call from `addTearDown`.
  Future<void> dispose() async {
    completePendingRead();
    await _foldEvents.close();
    await _capabilityEvents.close();
    await _rearDisplayEvents.close();
  }

  @override
  Future<FoldInfo> getFoldInfo() {
    final Completer<FoldInfo>? pending = _pendingRead;
    if (pending != null) {
      return pending.future;
    }
    return Future<FoldInfo>.value(_info);
  }

  @override
  Stream<FoldInfo> foldInfoStream() {
    _foldStreamRequests++;
    return _foldEvents.stream;
  }

  @override
  Future<BifoldCapabilities> getCapabilities() async => _capabilities;

  @override
  Stream<BifoldCapabilities> capabilitiesStream() => _capabilityEvents.stream;

  @override
  Future<String?> debugDescribeNativeApi() async => 'FakeBifoldPlatform';

  @override
  Future<RearDisplayAvailability> rearDisplayStatus() async => _rearDisplay;

  @override
  Stream<RearDisplayAvailability> rearDisplayAvailabilityStream() =>
      _rearDisplayEvents.stream;

  @override
  Future<bool> presentOnRearDisplay({
    required String entrypoint,
    String? libraryUri,
  }) async {
    rearDisplayCalls.add('present:$entrypoint');
    if (!rearDisplayRequestsSucceed) {
      return false;
    }
    emitRearDisplay(
      RearDisplayAvailability(
        presentation: RearDisplayStatus.active,
        transfer: _rearDisplay.transfer,
        isResolved: true,
      ),
    );
    return true;
  }

  @override
  Future<bool> transferToRearDisplay() async {
    rearDisplayCalls.add('transfer');
    if (!rearDisplayRequestsSucceed) {
      return false;
    }
    emitRearDisplay(
      RearDisplayAvailability(
        presentation: _rearDisplay.presentation,
        transfer: RearDisplayStatus.active,
        isResolved: true,
      ),
    );
    return true;
  }

  @override
  Future<void> endRearDisplay() async {
    rearDisplayCalls.add('end');
    emitRearDisplay(
      RearDisplayAvailability(
        presentation: _rearDisplay.presentation == RearDisplayStatus.active
            ? RearDisplayStatus.available
            : _rearDisplay.presentation,
        transfer: _rearDisplay.transfer == RearDisplayStatus.active
            ? RearDisplayStatus.available
            : _rearDisplay.transfer,
        isResolved: true,
      ),
    );
  }
}
