import 'dart:async';

// widgets.dart re-exports foundation selectively, so listEquals and
// ValueListenable need the explicit import.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../bifold_platform_interface.dart';
import '../capabilities.dart';
import '../fakes.dart';
import '../models.dart';

/// Supplies fold state to the widgets beneath it.
///
/// Place one near the root of the app, above anything that reads fold state:
///
/// ```dart
/// runApp(
///   const BifoldScope(
///     child: MyApp(),
///   ),
/// );
/// ```
///
/// Descendants read the current state with `Bifold.of(context)` and rebuild
/// whenever it changes. Before the first platform update arrives the scope
/// reports [FoldInfo.unsupported], so there is never a null or loading state
/// to handle.
///
/// A widget that only cares about one part of the state should say so, with
/// [Bifold.poseOf], [Bifold.hingeAngleOf], [Bifold.regionsOf] or
/// [Bifold.displayOf]. Those rebuild the caller only when that part changes,
/// which matters because the hinge angle changes continuously while the device
/// is being folded.
///
/// Nesting is allowed and the innermost scope wins, which is how a secondary
/// entrypoint — a rear-display presentation, say — gets its own fold state
/// without disturbing the main one.
///
/// For widget tests, use [BifoldScope.fake] to supply a fixed state without a
/// platform channel.
class BifoldScope extends StatefulWidget {
  /// Creates a scope that listens to the platform for fold state.
  const BifoldScope({required this.child, super.key})
      : _fakeInfo = null,
        _fakeCapabilities = null;

  /// Creates a scope that reports a fixed [info] and never touches the
  /// platform.
  ///
  /// This is the supported way to test fold-aware layouts. It needs no
  /// simulator, no iOS SDK, and no channel mocking, so the tests run anywhere:
  ///
  /// ```dart
  /// testWidgets('splits across the fold', (tester) async {
  ///   await tester.pumpWidget(
  ///     BifoldScope.fake(
  ///       info: FoldInfoFakes.partiallyOpen(viewSize: const Size(800, 1000)),
  ///       child: const MyReader(),
  ///     ),
  ///   );
  /// });
  /// ```
  ///
  /// See [FoldInfoFakes] for ready-made states covering each pose.
  const BifoldScope.fake({
    required FoldInfo info,
    required this.child,
    BifoldCapabilities? capabilities,
    super.key,
  })  : _fakeInfo = info,
        _fakeCapabilities = capabilities;

  /// The widget below this scope.
  final Widget child;

  final FoldInfo? _fakeInfo;
  final BifoldCapabilities? _fakeCapabilities;

  @override
  State<BifoldScope> createState() => _BifoldScopeState();
}

class _BifoldScopeState extends State<BifoldScope> {
  FoldInfo _info = FoldInfo.unsupported;
  BifoldCapabilities _capabilities = BifoldCapabilities.unresolved;
  StreamSubscription<FoldInfo>? _subscription;

  /// Whether this scope is currently mirroring [Bifold]'s capability state.
  ///
  /// Tracked rather than inferred, because the listener has to come off again
  /// when a scope switches to a fake or leaves the tree.
  bool _observingCapabilities = false;

  /// Whether the stream has delivered anything yet.
  ///
  /// Once it has, the seed query's result is stale by definition and is
  /// discarded rather than applied.
  bool _receivedFromStream = false;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(BifoldScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Both fakes matter. Comparing only the fold state meant that pumping the
    // same FoldInfo with a different capability profile -- the natural shape
    // of a table-driven capability test -- silently kept the old profile, so
    // the test passed while asserting the wrong thing.
    if (widget._fakeInfo != oldWidget._fakeInfo ||
        widget._fakeCapabilities != oldWidget._fakeCapabilities) {
      _bind();
    }
  }

  void _bind() {
    final FoldInfo? fake = widget._fakeInfo;
    if (fake != null) {
      _detach();
      _info = fake;
      // A fake fold state with no stated capabilities implies the capabilities
      // that state requires, so a test does not have to spell out both.
      _capabilities =
          widget._fakeCapabilities ?? BifoldCapabilityFakes.impliedBy(fake);
      return;
    }

    if (_subscription != null) {
      return;
    }
    _receivedFromStream = false;

    // Seed from the one-shot query so the first frame is not needlessly
    // unsupported on a device that already knows its pose. Regions still
    // arrive later, via the stream.
    //
    // The query can resolve after the stream has already delivered something
    // newer, so it only applies while the stream is still silent. Without that
    // guard a slow query overwrites live state with a stale reading.
    unawaited(
      BifoldPlatform.instance.getFoldInfo().then((FoldInfo info) {
        if (mounted && _subscription != null && !_receivedFromStream) {
          _update(info);
        }
      }),
    );

    // Capabilities come from [Bifold], never from a second subscription of our
    // own.
    //
    // This scope used to call Bifold.initialize() *and* listen to
    // BifoldPlatform.capabilitiesStream() itself, which meant two
    // subscriptions to one platform stream and two copies of the answer --
    // Bifold's static field and this instance field -- that could disagree,
    // and that disagreed per scope once an app nested two of them.
    //
    // [Bifold] is the single owner: it holds the resolved value, runs the one
    // subscription that keeps it current, and notifies here. That direction is
    // forced rather than chosen, because Bifold.capabilities is a synchronous
    // getter with no context and so cannot be derived from the widget tree,
    // whereas this scope can trivially be derived from it.
    Bifold._capabilityState.addListener(_onCapabilityState);
    _observingCapabilities = true;
    // Covers the case the listener cannot: capabilities already resolved
    // before this scope mounted, so no change is coming to be notified about.
    _capabilities = Bifold.capabilities;
    unawaited(Bifold.initialize());

    _subscription = BifoldPlatform.instance.foldInfoStream().listen(
      (FoldInfo info) {
        _receivedFromStream = true;
        _update(info);
      },
      // Errors are already reported by the platform implementation. Swallowing
      // them here keeps a transient platform failure from tearing down the
      // whole subtree.
      onError: (Object _) {},
    );
  }

  /// Releases everything [_bind] attached to the platform.
  void _detach() {
    _subscription?.cancel();
    _subscription = null;
    if (_observingCapabilities) {
      Bifold._capabilityState.removeListener(_onCapabilityState);
      _observingCapabilities = false;
    }
  }

  void _onCapabilityState() => _updateCapabilities(Bifold.capabilities);

  void _update(FoldInfo info) {
    if (!mounted || info == _info) {
      return;
    }
    setState(() => _info = info);
  }

  void _updateCapabilities(BifoldCapabilities capabilities) {
    if (!mounted || capabilities == _capabilities) {
      return;
    }
    setState(() => _capabilities = capabilities);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _BifoldCapabilityModel(
        capabilities: _capabilities,
        child: _BifoldModel(info: _info, child: widget.child),
      );
}

/// Carries capabilities separately from fold state.
///
/// Two inherited widgets rather than one, because the two change at very
/// different rates: fold state moves with the hinge, capabilities settle once
/// and then stay. Sharing a model would rebuild every fold-aware widget each
/// time a capability resolved.
class _BifoldCapabilityModel extends InheritedWidget {
  const _BifoldCapabilityModel({
    required this.capabilities,
    required super.child,
  });

  final BifoldCapabilities capabilities;

  @override
  bool updateShouldNotify(_BifoldCapabilityModel oldWidget) =>
      oldWidget.capabilities != capabilities;
}

/// The parts of [FoldInfo] a widget can depend on individually.
///
/// Deliberately private. The public surface is the four accessors on [Bifold]
/// that name these, so the set can grow in a 1.x release without adding a
/// value to an enum that consumer code might switch over exhaustively.
///
/// There is no aspect for the whole of [FoldInfo]: a dependency registered
/// with no aspect at all already means "notify me about everything", which is
/// what [Bifold.of] and [Bifold.maybeOf] rely on.
enum _FoldAspect {
  /// [FoldInfo.pose].
  pose,

  /// [FoldInfo.hingeAngle].
  hingeAngle,

  /// [FoldInfo.regions], compared element by element.
  regions,

  /// [FoldInfo.display].
  display,
}

/// Publishes fold state so a dependent can name the part it cares about.
///
/// An [InheritedModel] rather than a plain [InheritedWidget] because the hinge
/// angle changes continuously while a device is being folded, and
/// [FoldInfo]'s equality includes it. With one undivided model, a widget that
/// only reads the pose rebuilt on every angle sample — tens of times a second,
/// once per call site. Aspects let the framework skip the dependents whose
/// part of the state did not move.
class _BifoldModel extends InheritedModel<_FoldAspect> {
  const _BifoldModel({required this.info, required super.child});

  final FoldInfo info;

  @override
  bool updateShouldNotify(_BifoldModel oldWidget) => oldWidget.info != info;

  @override
  bool updateShouldNotifyDependent(
    _BifoldModel oldWidget,
    Set<_FoldAspect> aspects,
  ) {
    for (final _FoldAspect aspect in aspects) {
      final bool changed = switch (aspect) {
        _FoldAspect.pose => oldWidget.info.pose != info.pose,
        _FoldAspect.hingeAngle => oldWidget.info.hingeAngle != info.hingeAngle,
        _FoldAspect.regions =>
          !listEquals(oldWidget.info.regions, info.regions),
        _FoldAspect.display => oldWidget.info.display != info.display,
      };
      if (changed) {
        return true;
      }
    }
    return false;
  }
}

/// A [ValueListenable] view of the platform's fold state.
///
/// Subscribes on its first listener and unsubscribes with its last, so holding
/// a reference to it costs nothing and an app that stops listening stops the
/// platform work too.
class _FoldInfoListenable extends ChangeNotifier
    implements ValueListenable<FoldInfo> {
  FoldInfo _value = FoldInfo.unsupported;
  StreamSubscription<FoldInfo>? _subscription;

  @override
  FoldInfo get value => _value;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _subscription ??= BifoldPlatform.instance.foldInfoStream().listen(
      (FoldInfo info) {
        if (info == _value) {
          return;
        }
        _value = info;
        notifyListeners();
      },
      // Consistent with BifoldScope: the platform implementation has already
      // reported the failure, and tearing a listenable down over a transient
      // one would be worse than keeping the last known state.
      onError: (Object _) {},
    );
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _subscription?.cancel();
      _subscription = null;
    }
  }

  /// Drops the subscription and the last known value. Tests only.
  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _value = FoldInfo.unsupported;
  }
}

/// Reads fold state from the widget tree.
///
/// Requires a [BifoldScope] ancestor. See [Bifold.of] and [Bifold.maybeOf] for
/// the widget-tree accessors, [poseOf], [hingeAngleOf], [regionsOf] and
/// [displayOf] for narrower ones, and [Bifold.current], [Bifold.stream] and
/// [Bifold.listenable] for reading fold state outside a build method.
abstract final class Bifold {
  /// The current fold state, rebuilding the caller when **anything** in it
  /// changes.
  ///
  /// The default, and the right choice for a widget that reads several parts
  /// of the state. Note what "anything" includes: [FoldInfo.hingeAngle] moves
  /// continuously while a device is being folded, so a widget that reads only
  /// the pose through this rebuilds on every sample. Use [poseOf],
  /// [hingeAngleOf], [regionsOf] or [displayOf] to depend on one part.
  ///
  /// Throws a [FlutterError] in debug mode if there is no [BifoldScope]
  /// ancestor, because silently reporting "no fold" would make a missing scope
  /// look like a non-foldable device. Use [maybeOf] where the scope is
  /// genuinely optional.
  static FoldInfo of(BuildContext context) =>
      _require(context, maybeOf(context), 'Bifold.of()');

  /// The current fold state, or null when there is no [BifoldScope] ancestor.
  ///
  /// Rebuilds the caller when any part of the state changes.
  static FoldInfo? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BifoldModel>()?.info;

  /// How far the device is folded, rebuilding the caller only when that
  /// changes.
  ///
  /// The accessor for a layout that switches between shut, part-way open and
  /// flat: an angle sample that does not cross into another pose rebuilds
  /// nothing.
  ///
  /// Throws a [FlutterError] in debug mode with no [BifoldScope] ancestor,
  /// exactly as [of] does.
  static FoldPose poseOf(BuildContext context) =>
      _dependOn(context, _FoldAspect.pose, 'Bifold.poseOf()').pose;

  /// The hinge angle in radians, rebuilding the caller only when it changes.
  ///
  /// Null when the platform reports no reading; see [FoldInfo.hingeAngle] for
  /// what that means and when it happens. This is the one aspect that does
  /// change continuously, so a widget reading it is expected to rebuild often
  /// — which is the point of letting everything else opt out.
  ///
  /// Throws a [FlutterError] in debug mode with no [BifoldScope] ancestor,
  /// exactly as [of] does.
  static double? hingeAngleOf(BuildContext context) =>
      _dependOn(context, _FoldAspect.hingeAngle, 'Bifold.hingeAngleOf()')
          .hingeAngle;

  /// The reserved regions, rebuilding the caller only when they change.
  ///
  /// Compared element by element, so a region list that is rebuilt from an
  /// identical platform payload does not count as a change.
  ///
  /// Throws a [FlutterError] in debug mode with no [BifoldScope] ancestor,
  /// exactly as [of] does.
  static List<FoldRegion> regionsOf(BuildContext context) =>
      _dependOn(context, _FoldAspect.regions, 'Bifold.regionsOf()').regions;

  /// Which display the app is on, rebuilding the caller only when that
  /// changes.
  ///
  /// Throws a [FlutterError] in debug mode with no [BifoldScope] ancestor,
  /// exactly as [of] does.
  static FoldDisplay displayOf(BuildContext context) =>
      _dependOn(context, _FoldAspect.display, 'Bifold.displayOf()').display;

  /// Registers a dependency on one [aspect] and returns the whole state.
  static FoldInfo _dependOn(
    BuildContext context,
    _FoldAspect aspect,
    String method,
  ) {
    final _BifoldModel? model =
        InheritedModel.inheritFrom<_BifoldModel>(context, aspect: aspect);
    return _require(context, model?.info, method);
  }

  /// Complains about a missing scope in debug, and degrades in release.
  ///
  /// Shared by every fold-state accessor so they all fail the same way: a
  /// missing scope is a wiring mistake, and reporting "no fold" instead would
  /// make it look like a non-foldable device. [capabilitiesOf] deliberately
  /// differs — see its own documentation.
  static FoldInfo _require(
    BuildContext context,
    FoldInfo? info,
    String method,
  ) {
    assert(() {
      if (info == null) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('$method called without a BifoldScope ancestor.'),
          ErrorDescription(
            'Fold state is supplied by a BifoldScope, and no ancestor of the '
            'calling widget is one.',
          ),
          ErrorHint(
            'Wrap your app in a BifoldScope, typically at the root:\n'
            '  runApp(const BifoldScope(child: MyApp()));\n'
            'In tests, use BifoldScope.fake(info: ..., child: ...) to supply '
            'a fold state directly.',
          ),
          context.describeElement('The context used was'),
        ]);
      }
      return true;
    }());
    return info ?? FoldInfo.unsupported;
  }

  /// Reads the fold state once, without a [BifoldScope].
  ///
  /// Two things arrive late and so can be missing from an early call:
  /// reserved regions, which the platform only produces after its first
  /// layout pass, and [FoldInfo.hingeAngle], whose first update is delivered
  /// asynchronously after the hinge is first observed. A one-shot read taken
  /// immediately at launch will typically report neither.
  ///
  /// Prefer [Bifold.of] or [stream]. This exists for one-shot checks such as
  /// logging device capability at startup.
  static Future<FoldInfo> get current => BifoldPlatform.instance.getFoldInfo();

  /// The single owner of resolved capabilities.
  ///
  /// A notifier rather than a plain field so that `BifoldScope` can mirror it
  /// without opening a second subscription to the platform. See the comment in
  /// `_BifoldScopeState._bind`.
  static final ValueNotifier<BifoldCapabilities> _capabilityState =
      ValueNotifier<BifoldCapabilities>(BifoldCapabilities.unresolved);

  static Future<BifoldCapabilities>? _resolution;
  static StreamSubscription<BifoldCapabilities>? _capabilitySubscription;
  static _FoldInfoListenable? _listenable;

  /// What this device can do, right now, synchronously.
  ///
  /// Returns [BifoldCapabilities.unresolved] until the platform has answered,
  /// which means **a false `hasFold` here can mean "not known yet"**. Check
  /// [BifoldCapabilities.isResolved], await [capabilitiesReady], or use
  /// [capabilitiesOf] in a widget, which rebuilds when the answer arrives.
  ///
  /// Never throws, on any platform.
  static BifoldCapabilities get capabilities => _capabilityState.value;

  /// Establishes capabilities, and keeps them up to date.
  ///
  /// Optional: `BifoldScope` calls it, and [capabilitiesOf] does not need it.
  /// Call it directly when non-widget code wants [capabilities] populated
  /// before it runs. Safe to call repeatedly — the work happens once.
  static Future<void> initialize() => capabilitiesReady;

  /// Completes once the platform has given its **first** answer.
  ///
  /// For code that must not race the synchronous getter into a false
  /// `hasFold`:
  ///
  /// ```dart
  /// await Bifold.capabilitiesReady;
  /// if (Bifold.capabilities.hasHingeAngle) {
  ///   // Worth subscribing to the angle on this device.
  /// }
  /// ```
  ///
  /// Note which value that example reads. The future completes with a
  /// *snapshot* taken at first resolution, and capabilities keep improving
  /// after it: a statically-known hinge resolves immediately, while posture
  /// and rear-display support only settle once something has been observed.
  /// Awaiting this and then using its result would pin the earliest, least
  /// informed answer. Await it to know the platform has spoken, then read
  /// [capabilities], or use [capabilitiesStream] to follow every improvement.
  ///
  /// ## Lifetime
  ///
  /// The first call starts one subscription to the platform's capability
  /// stream, and that subscription lives for the rest of the process. This is
  /// deliberate: [capabilities] is a synchronous getter with no owner to
  /// dispose, so there is nothing whose death could reasonably end it, and a
  /// capability that stopped being followed would silently go stale. It is a
  /// single subscription however many times this is called, and however many
  /// `BifoldScope`s the app builds. No public API cancels it; [debugReset]
  /// does, for tests.
  static Future<BifoldCapabilities> get capabilitiesReady {
    return _resolution ??= () async {
      try {
        final BifoldCapabilities resolved =
            await BifoldPlatform.instance.getCapabilities();
        _capabilityState.value = resolved;
        // Keep following: a capability can move from unknown to supported when
        // the platform finally reports something, long after the first answer.
        _capabilitySubscription ??=
            BifoldPlatform.instance.capabilitiesStream().listen(
                  (BifoldCapabilities latest) =>
                      _capabilityState.value = latest,
                  onError: (Object _) {},
                );
        return resolved;
      } on UnimplementedError {
        // A BifoldPlatform predating capabilities. Reporting unresolved is
        // truthful: that implementation cannot say either way.
        return _capabilityState.value;
      }
    }();
  }

  /// Capabilities as a stream, without a `BifoldScope`.
  ///
  /// Emits whenever something new is established. A capability never moves
  /// from supported back to unsupported.
  ///
  /// This opens a subscription of its own, which the caller owns and should
  /// cancel. Prefer [capabilitiesOf] in a widget and [capabilities] after
  /// [capabilitiesReady] elsewhere; this is for code that genuinely wants
  /// every improvement as an event.
  static Stream<BifoldCapabilities> get capabilitiesStream =>
      BifoldPlatform.instance.capabilitiesStream();

  /// What this device can do, rebuilding the caller when that changes.
  ///
  /// The widget-side accessor, and the one to prefer: capabilities can improve
  /// after the first frame, and a synchronous read cannot rebuild anything
  /// when they do.
  ///
  /// Returns [BifoldCapabilities.unresolved] when there is no `BifoldScope`
  /// ancestor rather than throwing, unlike [of] and the aspect accessors.
  /// The asymmetry is deliberate: "nothing has been established" is exactly
  /// what a missing scope means for a capability, and it is a value this
  /// method can honestly return, whereas there is no fold state that honestly
  /// describes "nobody is listening to the platform".
  static BifoldCapabilities capabilitiesOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_BifoldCapabilityModel>()
          ?.capabilities ??
      BifoldCapabilities.unresolved;

  /// Everything known about this device, as text to paste into a bug report.
  ///
  /// Capabilities with the platform signal behind each one, the current fold
  /// state, and what the running OS actually exposes. Intended to be shown to
  /// a user and copied by them.
  ///
  /// **Nothing is transmitted.** This builds a string and returns it; sending
  /// it anywhere is the app's decision. It carries no identifier beyond what
  /// the OS reports about the model.
  static Future<String> diagnosticReport() async {
    final BifoldCapabilities capabilities = await capabilitiesReady;
    final FoldInfo info = await current;
    final String? native =
        await BifoldPlatform.instance.debugDescribeNativeApi();

    final StringBuffer buffer = StringBuffer('bifold diagnostic report\n');
    buffer.writeln('\nCapabilities (resolved: ${capabilities.isResolved})');
    buffer.writeln('  formFactor: ${capabilities.formFactor.name}');
    for (final FoldFeature feature in FoldFeature.values) {
      final CapabilityEvidence evidence = capabilities.evidenceOf(feature);
      buffer.writeln(
        '  ${feature.name}: ${evidence.status.name}'
        '${evidence.source == null ? '' : '  <- ${evidence.source}'}',
      );
    }
    if (capabilities.rearDisplayModes.isNotEmpty) {
      buffer.writeln(
        '  rearDisplayModes: '
        '${capabilities.rearDisplayModes.map((RearDisplayMode m) => m.name).join(', ')}',
      );
    }
    buffer.writeln('\nCurrent state');
    buffer.writeln('  $info');
    buffer.writeln('\nPlatform');
    buffer.writeln(native ?? '  no native implementation on this platform');
    return buffer.toString();
  }

  /// A description of the fold APIs the running OS actually exposes.
  ///
  /// Reports the real selector names, type encodings and class members that
  /// this device offers, read from the Objective-C runtime. Intended for bug
  /// reports: a user on hardware this package has never seen can run it and
  /// paste the result, which is more useful than a version number.
  ///
  /// Returns null on platforms with no native implementation. Reads only —
  /// nothing is invoked with side effects and nothing is mutated.
  @Deprecated(
    'Use Bifold.diagnosticReport(), which includes this along with '
    'capabilities and current state. Will be removed in 2.0.0.',
  )
  static Future<String?> debugDescribeNativeApi() =>
      BifoldPlatform.instance.debugDescribeNativeApi();

  /// Forgets resolved capabilities and the [listenable]'s subscription.
  ///
  /// Tests only. Both are process-lifetime by design, which would otherwise
  /// leak state from one test into the next.
  @visibleForTesting
  static void debugReset() {
    _capabilityState.value = BifoldCapabilities.unresolved;
    _resolution = null;
    _capabilitySubscription?.cancel();
    _capabilitySubscription = null;
    _listenable?.reset();
  }

  /// The fold state stream, without a [BifoldScope].
  ///
  /// Emits the current state on listen, then on every change. Use this for
  /// non-widget code such as a controller or a bloc; widgets should use
  /// [Bifold.of].
  ///
  /// Prefer [listenable] unless you actually want a stream: it carries the
  /// current value with it, so a controller does not have to hold both a
  /// subscription and a copy of the last event.
  static Stream<FoldInfo> get stream =>
      BifoldPlatform.instance.foldInfoStream();

  /// The fold state as a [ValueListenable], without a [BifoldScope].
  ///
  /// For non-widget code — a controller, a bloc, an animation — that wants the
  /// current state *and* a notification when it changes, without writing the
  /// subscribe/store/cancel wrapper around [stream] by hand:
  ///
  /// ```dart
  /// class HingeController extends ChangeNotifier {
  ///   HingeController() {
  ///     Bifold.listenable.addListener(notifyListeners);
  ///   }
  ///
  ///   double? get angle => Bifold.listenable.value;
  ///
  ///   @override
  ///   void dispose() {
  ///     Bifold.listenable.removeListener(notifyListeners);
  ///     super.dispose();
  ///   }
  /// }
  /// ```
  ///
  /// It also composes with the framework directly: pass it to a
  /// [ValueListenableBuilder], or to an [AnimatedBuilder], and rebuild only
  /// that builder rather than a whole subtree.
  ///
  /// One object for the whole process, shared by every caller, and one
  /// platform subscription behind it however many listeners it has. It
  /// subscribes when it gains its first listener and unsubscribes when it
  /// loses its last, so its value is [FoldInfo.unsupported] until something
  /// listens — add the listener before reading it. Equal consecutive states do
  /// not notify.
  ///
  /// This is independent of [BifoldScope]: it reads the platform, so it works
  /// with no scope in the tree and does not see a `BifoldScope.fake`. Widget
  /// tests should use the scope; a test of a controller built on this should
  /// install a `FakeBifoldPlatform`.
  static ValueListenable<FoldInfo> get listenable =>
      _listenable ??= _FoldInfoListenable();
}
