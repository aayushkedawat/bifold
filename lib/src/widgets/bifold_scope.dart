import 'dart:async';

import 'package:flutter/widgets.dart';

import '../bifold_platform_interface.dart';
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
  const BifoldScope({required this.child, super.key}) : _fakeInfo = null;

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
    super.key,
  }) : _fakeInfo = info;

  /// The widget below this scope.
  final Widget child;

  final FoldInfo? _fakeInfo;

  @override
  State<BifoldScope> createState() => _BifoldScopeState();
}

class _BifoldScopeState extends State<BifoldScope> {
  FoldInfo _info = FoldInfo.unsupported;
  StreamSubscription<FoldInfo>? _subscription;

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
      _info = fake;
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

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _BifoldModel(info: _info, child: widget.child);
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
  static FoldInfo? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_BifoldModel>()
      ?.info;

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

  /// A description of the fold APIs the running OS actually exposes.
  ///
  /// Reports the real selector names, type encodings and class members that
  /// this device offers, read from the Objective-C runtime. Intended for bug
  /// reports: a user on hardware this package has never seen can run it and
  /// paste the result, which is more useful than a version number.
  ///
  /// Returns null on platforms with no native implementation. Reads only —
  /// nothing is invoked with side effects and nothing is mutated.
  static Future<String?> debugDescribeNativeApi() =>
      BifoldPlatform.instance.debugDescribeNativeApi();

  /// The fold state stream, without a [BifoldScope].
  ///
  /// Emits the current state on listen, then on every change. Use this for
  /// non-widget code such as a controller or a bloc; widgets should use
  /// [Bifold.of].
  static Stream<FoldInfo> get stream =>
      BifoldPlatform.instance.foldInfoStream();
}
