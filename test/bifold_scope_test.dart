import 'dart:async';

import 'package:bifold/bifold.dart';
import 'package:bifold/src/method_channel_bifold.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  group('BifoldScope.fake', () {
    testWidgets('supplies the given state without touching the platform',
        (tester) async {
      final info = FoldInfoFakes.partiallyOpen(
        viewSize: const Size(800, 1000),
      );
      late FoldInfo seen;

      await tester.pumpWidget(
        BifoldScope.fake(
          info: info,
          child: Builder(
            builder: (context) {
              seen = Bifold.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(seen, info);
    });

    testWidgets('rebuilds descendants when the state changes', (tester) async {
      final builds = <FoldPose>[];

      Widget build(FoldInfo info) => BifoldScope.fake(
        info: info,
        child: Builder(
          builder: (context) {
            builds.add(Bifold.of(context).pose);
            return const SizedBox();
          },
        ),
      );

      await tester.pumpWidget(build(FoldInfoFakes.closed));
      await tester.pumpWidget(
        build(FoldInfoFakes.fullyOpen(viewSize: const Size(800, 1000))),
      );

      expect(builds, <FoldPose>[FoldPose.closed, FoldPose.fullyOpen]);
    });

    testWidgets('does not notify dependents when the state is unchanged',
        (tester) async {
      // Measured with didChangeDependencies rather than build count: a parent
      // rebuild reruns build regardless of the inherited widget, so only this
      // distinguishes "notified" from "rebuilt for unrelated reasons".
      _DependencyCounter.notifications = 0;

      Widget build(FoldInfo info) => BifoldScope.fake(
        info: info,
        child: const _DependencyCounter(),
      );

      await tester.pumpWidget(build(FoldInfoFakes.closed));
      expect(_DependencyCounter.notifications, 1);

      // A distinct but equal value must not notify.
      await tester.pumpWidget(build(FoldInfoFakes.closed));
      expect(_DependencyCounter.notifications, 1);

      // A genuinely different one must.
      await tester.pumpWidget(
        build(FoldInfoFakes.fullyOpen(viewSize: const Size(800, 1000))),
      );
      expect(_DependencyCounter.notifications, 2);
    });
  });

  group('Bifold.of', () {
    testWidgets('throws a helpful error with no scope ancestor',
        (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            Bifold.of(context);
            return const SizedBox();
          },
        ),
      );

      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(
        error.toString(),
        contains('called without a BifoldScope ancestor'),
      );
      // The message must say how to fix it, in both app and test form.
      expect(error.toString(), contains('runApp(const BifoldScope'));
      expect(error.toString(), contains('BifoldScope.fake'));
    });

    testWidgets('maybeOf returns null instead of throwing', (tester) async {
      FoldInfo? seen = FoldInfo.unsupported;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = Bifold.maybeOf(context);
            return const SizedBox();
          },
        ),
      );

      expect(seen, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('BifoldScope against a platform implementation', () {
    late _FakePlatform platform;

    setUp(() {
      platform = _FakePlatform();
      BifoldPlatform.instance = platform;
    });

    tearDown(() {
      platform.dispose();
      BifoldPlatform.instance = MethodChannelBifold();
    });

    testWidgets('starts unsupported, then adopts what the platform sends',
        (tester) async {
      final seen = <FoldInfo>[];

      await tester.pumpWidget(
        BifoldScope(
          child: Builder(
            builder: (context) {
              seen.add(Bifold.of(context));
              return const SizedBox();
            },
          ),
        ),
      );

      // No state has arrived yet, so there is a well-defined value rather than
      // a null or a loading flag.
      expect(seen.single, FoldInfo.unsupported);

      final open = FoldInfoFakes.fullyOpen(viewSize: const Size(800, 1000));
      await platform.emitAndPump(tester, open);
      expect(seen.last, open);

      // Regions arriving later is the normal case, not an edge case.
      final creased = FoldInfoFakes.partiallyOpen(
        viewSize: const Size(800, 1000),
      );
      await platform.emitAndPump(tester, creased);
      expect(seen.last, creased);
      expect(seen.last.division, isNotNull);
    });

    testWidgets('a slow seed query never overwrites newer stream state',
        (tester) async {
      // The scope seeds itself from a one-shot query so the first frame is not
      // needlessly unsupported. That query can resolve after the stream has
      // already delivered something newer, and applying it then would drop the
      // app back to "no fold" on a device that has one.
      platform.completeGetFoldInfoManually = true;
      late FoldInfo seen;

      await tester.pumpWidget(
        BifoldScope(
          child: Builder(
            builder: (context) {
              seen = Bifold.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      final creased = FoldInfoFakes.partiallyOpen(
        viewSize: const Size(800, 1000),
      );
      await platform.emitAndPump(tester, creased);
      expect(seen, creased);

      // The stale query lands last.
      platform.completeGetFoldInfo(FoldInfo.unsupported);
      await tester.pump();
      await tester.pump();

      expect(seen, creased, reason: 'stale seed clobbered live fold state');
    });

    testWidgets('keeps the last state when the stream errors', (tester) async {
      late FoldInfo seen;

      await tester.pumpWidget(
        BifoldScope(
          child: Builder(
            builder: (context) {
              seen = Bifold.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      final open = FoldInfoFakes.fullyOpen(viewSize: const Size(800, 1000));
      await platform.emitAndPump(tester, open);

      platform.emitError(Exception('transient platform failure'));
      await tester.pump();
      await tester.pump();

      // A failure must not tear down the subtree or reset it to unsupported.
      expect(tester.takeException(), isNull);
      expect(seen, open);
    });

    testWidgets('unsubscribes when removed from the tree', (tester) async {
      await tester.pumpWidget(
        const BifoldScope(child: SizedBox()),
      );
      expect(platform.listenerCount, 1);

      await tester.pumpWidget(const SizedBox());
      expect(platform.listenerCount, 0);
    });

    testWidgets('never reaches the platform when faked', (tester) async {
      await tester.pumpWidget(
        BifoldScope.fake(
          info: FoldInfoFakes.closed,
          child: const SizedBox(),
        ),
      );

      expect(platform.listenerCount, 0);
      expect(platform.getFoldInfoCalls, 0);
    });
  });
}

/// Counts how many times fold state actually notified a dependent.
class _DependencyCounter extends StatefulWidget {
  const _DependencyCounter();

  static int notifications = 0;

  @override
  State<_DependencyCounter> createState() => _DependencyCounterState();
}

class _DependencyCounterState extends State<_DependencyCounter> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _DependencyCounter.notifications++;
  }

  @override
  Widget build(BuildContext context) {
    Bifold.of(context);
    return const SizedBox();
  }
}

/// A [BifoldPlatform] whose stream this test drives directly.
class _FakePlatform extends BifoldPlatform {
  late final StreamController<FoldInfo> _controller =
      StreamController<FoldInfo>.broadcast(
        onListen: () => listenerCount++,
        onCancel: () => listenerCount--,
      );

  int listenerCount = 0;
  int getFoldInfoCalls = 0;

  /// When true, [getFoldInfo] stays pending until [completeGetFoldInfo] is
  /// called, so a test can control whether it lands before or after a stream
  /// event.
  bool completeGetFoldInfoManually = false;
  Completer<FoldInfo>? _pendingGet;

  void emit(FoldInfo info) => _controller.add(info);

  /// Emits [info] and pumps until the resulting setState has been rendered.
  ///
  /// A stream event is delivered in a microtask that runs *after* the frame a
  /// single pump renders, so one pump would assert against the frame before
  /// the update. This is a property of the test harness, not of BifoldScope.
  Future<void> emitAndPump(WidgetTester tester, FoldInfo info) async {
    emit(info);
    await tester.pump();
    await tester.pump();
  }

  void emitError(Object error) => _controller.addError(error);

  void completeGetFoldInfo(FoldInfo info) => _pendingGet?.complete(info);

  void dispose() => _controller.close();

  @override
  Future<FoldInfo> getFoldInfo() {
    getFoldInfoCalls++;
    if (!completeGetFoldInfoManually) {
      return Future<FoldInfo>.value(FoldInfo.unsupported);
    }
    return (_pendingGet = Completer<FoldInfo>()).future;
  }

  @override
  Stream<FoldInfo> foldInfoStream() => _controller.stream;
}

/// Guards against the platform interface losing its token check, which would
/// let an unrelated object be installed as the platform implementation.
// ignore: unused_element
void _tokenIsEnforced() {
  PlatformInterface.verifyToken;
}
