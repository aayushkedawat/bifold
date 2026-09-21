import 'dart:async';

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
  StreamSubscription<BifoldCapabilities>? _capabilitySubscription;

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
    if (widget._fakeInfo != oldWidget._fakeInfo) {
      _bind();
    }
  }

  void _bind() {
    final FoldInfo? fake = widget._fakeInfo;
    if (fake != null) {
      _subscription?.cancel();
      _subscription = null;
      _capabilitySubscription?.cancel();
      _capabilitySubscription = null;
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

    unawaited(
      Bifold.initialize().then((_) {
        if (mounted) {
          _updateCapabilities(Bifold.capabilities);
        }
      }),
    );
    try {
      _capabilitySubscription =
          BifoldPlatform.instance.capabilitiesStream().listen(
                _updateCapabilities,
                onError: (Object _) {},
              );
    } on UnimplementedError {
      // A BifoldPlatform written before capabilities existed. Fold state still
      // works; capabilities stay unresolved, which is the honest answer. This
      // must not abort the rest of binding.
    }

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
    _subscription?.cancel();
    _capabilitySubscription?.cancel();
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

class _BifoldModel extends InheritedWidget {
  const _BifoldModel({required this.info, required super.child});

  final FoldInfo info;

  @override
  bool updateShouldNotify(_BifoldModel oldWidget) => oldWidget.info != info;
}

/// Reads fold state from the widget tree.
///
/// Requires a [BifoldScope] ancestor. See [Bifold.of] and [Bifold.maybeOf] for
/// the widget-tree accessors, and [Bifold.current] and [Bifold.stream] for
/// reading fold state outside a build method.
abstract final class Bifold {
  /// The current fold state, rebuilding the caller when it changes.
  ///
  /// Throws a [FlutterError] in debug mode if there is no [BifoldScope]
  /// ancestor, because silently reporting "no fold" would make a missing scope
  /// look like a non-foldable device. Use [maybeOf] where the scope is
  /// genuinely optional.
  static FoldInfo of(BuildContext context) {
    final FoldInfo? info = maybeOf(context);
    assert(() {
      if (info == null) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('Bifold.of() called without a BifoldScope ancestor.'),
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

  /// The current fold state, or null when there is no [BifoldScope] ancestor.
  ///
  /// Rebuilds the caller when the state changes.
  static FoldInfo? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BifoldModel>()?.info;

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

  static BifoldCapabilities _capabilities = BifoldCapabilities.unresolved;
  static Future<BifoldCapabilities>? _resolution;
  static StreamSubscription<BifoldCapabilities>? _capabilitySubscription;

  /// What this device can do, right now, synchronously.
  ///
  /// Returns [BifoldCapabilities.unresolved] until the platform has answered,
  /// which means **a false `hasFold` here can mean "not known yet"**. Check
  /// [BifoldCapabilities.isResolved], await [capabilitiesReady], or use
  /// [capabilitiesOf] in a widget, which rebuilds when the answer arrives.
  ///
  /// Never throws, on any platform.
  static BifoldCapabilities get capabilities => _capabilities;

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
  static Future<BifoldCapabilities> get capabilitiesReady {
    return _resolution ??= () async {
      try {
        final BifoldCapabilities resolved =
            await BifoldPlatform.instance.getCapabilities();
        _capabilities = resolved;
        // Keep following: a capability can move from unknown to supported when
        // the platform finally reports something, long after the first answer.
        _capabilitySubscription ??=
            BifoldPlatform.instance.capabilitiesStream().listen(
                  (BifoldCapabilities latest) => _capabilities = latest,
                  onError: (Object _) {},
                );
        return resolved;
      } on UnimplementedError {
        // A BifoldPlatform predating capabilities. Reporting unresolved is
        // truthful: that implementation cannot say either way.
        return _capabilities;
      }
    }();
  }

  /// Capabilities as a stream, without a `BifoldScope`.
  ///
  /// Emits whenever something new is established. A capability never moves
  /// from supported back to unsupported.
  static Stream<BifoldCapabilities> get capabilitiesStream =>
      BifoldPlatform.instance.capabilitiesStream();

  /// What this device can do, rebuilding the caller when that changes.
  ///
  /// The widget-side accessor, and the one to prefer: capabilities can improve
  /// after the first frame, and a synchronous read cannot rebuild anything
  /// when they do.
  ///
  /// Returns [BifoldCapabilities.unresolved] when there is no `BifoldScope`
  /// ancestor rather than throwing, because "not established" is exactly what
  /// that situation is.
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
    'capabilities and current state. Will be removed in 0.4.0.',
  )
  static Future<String?> debugDescribeNativeApi() =>
      BifoldPlatform.instance.debugDescribeNativeApi();

  /// Forgets resolved capabilities. Tests only.
  @visibleForTesting
  static void debugReset() {
    _capabilities = BifoldCapabilities.unresolved;
    _resolution = null;
    _capabilitySubscription?.cancel();
    _capabilitySubscription = null;
  }

  /// The fold state stream, without a [BifoldScope].
  ///
  /// Emits the current state on listen, then on every change. Use this for
  /// non-widget code such as a controller or a bloc; widgets should use
  /// [Bifold.of].
  static Stream<FoldInfo> get stream =>
      BifoldPlatform.instance.foldInfoStream();
}
