// Compile-checks the code in README.md.
//
// The examples are the first thing anyone runs, so they are held to the same
// analyzer bar as the package itself rather than trusted to stay correct.

import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// --- Quick start ---------------------------------------------------------
Widget readState(BuildContext context) {
  final info = Bifold.of(context);
  if (info.division != null) {
    return const Text('creased');
  }
  return Column(
    children: <Widget>[
      Text('Pose: ${info.pose.name}'),
      if (info.hingeAngleDegrees case final degrees?)
        Text('Open to ${degrees.toStringAsFixed(0)}°'),
      Text('On the ${info.display.name} display'),
      Text('${info.horizontalSizeClass.name}/${info.verticalSizeClass.name}'),
      Text('${info.isRegular} ${info.verticalBarEdge.name}'),
      Text('${info.activeRegions.length} ${info.regions.length}'),
      Text('${info.isFoldable} ${FoldInfo.unsupported.pose.name}'),
    ],
  );
}

void listenOutsideTheTree() {
  Bifold.stream.listen((FoldInfo info) {});
  Bifold.current.then((FoldInfo info) {});
  Bifold.debugDescribeNativeApi().then((String? report) {});
}

Widget maybe(BuildContext context) =>
    Text(Bifold.maybeOf(context)?.pose.name ?? 'none');

// --- Layout --------------------------------------------------------------
Widget split() => BifoldSplit(
      fallback: BifoldSplitFallback.sideBySide,
      spacing: 16,
      start: const Text('start'),
      end: const Text('end'),
    );

Widget grid() => BifoldGrid(
      tileExtent: 160,
      spacing: 8,
      padding: const EdgeInsets.all(12),
      children: const <Widget>[Text('tile')],
    );

Widget scaffold(int index, void Function(int) onSelect) => BifoldScaffold(
      appBar: AppBar(title: const Text('Inbox')),
      selectedIndex: index,
      onDestinationSelected: onSelect,
      destinations: const <BifoldDestination>[
        BifoldDestination(icon: Icon(Icons.inbox), label: 'Inbox'),
        BifoldDestination(icon: Icon(Icons.send), label: 'Sent'),
      ],
      body: const Text('body'),
    );

void dialog(BuildContext context) {
  showDialog<void>(
    context: context,
    anchorPoint: bifoldAnchorPoint(context),
    builder: (BuildContext context) => const AlertDialog(title: Text('Saved')),
  );
}

// --- Camera --------------------------------------------------------------
@pragma('vm:entry-point')
void captureAccessoryMain() => runApp(const Text('subject'));

Future<void> camera() async {
  if (await BifoldCaptureAccessory.isSupported) {
    await BifoldCaptureAccessory.register(entrypoint: 'captureAccessoryMain');
    await BifoldCaptureAccessory.setEnabled(true);
  }
  BifoldCaptureAccessory.availability.listen((bool available) {});
  await BifoldCaptureAccessory.isAvailable;
  await BifoldCaptureAccessory.unregister();
}

// --- Diagnostics ---------------------------------------------------------
Widget overlay(Widget child) => BifoldDebugOverlay(enabled: true, child: child);
Widget bridge(Widget child) => BifoldDisplayFeatures(child: child);

Future<void> arrangement() async {
  final ArrangementMeasurement? measured = await BifoldArrangement.measure(
    size: const Size(871, 669),
    axis: ArrangementAxis.vertical,
  );
  if (measured != null && measured.isSplit) {
    final ArrangementPane pane = measured.primary;
    debugPrint('${pane.bounds} ${pane.isVisible} ${measured.axis.name}');
  }
  await BifoldArrangement.release();
}

// --- Region members quoted in the API table ------------------------------
void regionMembers(FoldRegion region) {
  debugPrint(
    '${region.kind.name} ${region.frame} ${region.reservedRect} '
    '${region.margins} ${region.isActive} '
    '${region.isSeparating(const Size(800, 1000))} ${region.isHorizontal}',
  );
}

void main() {
  const Size size = Size(800, 1000);

  /// Pumps one example on its own, so an overflow in the harness cannot be
  /// mistaken for one in the package.
  Future<void> pumpExample(
    WidgetTester tester,
    Widget Function(BuildContext) build,
  ) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BifoldScope.fake(
        info: FoldInfoFakes.partiallyOpen(viewSize: size),
        child: MaterialApp(home: Builder(builder: build)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets('the fold-state examples build', (tester) async {
    await pumpExample(tester, readState);
    await pumpExample(tester, maybe);
  });

  testWidgets('the layout examples build', (tester) async {
    await pumpExample(tester, (_) => split());
    await pumpExample(tester, (_) => grid());
  });

  testWidgets('the scaffold example builds', (tester) async {
    await tester.pumpWidget(
      BifoldScope.fake(
        info: FoldInfoFakes.closed,
        child: MaterialApp(home: scaffold(0, (_) {})),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the diagnostics examples build', (tester) async {
    await tester.pumpWidget(
      BifoldScope.fake(
        info: FoldInfoFakes.fullyOpen(viewSize: size),
        child: MaterialApp(
          builder: (BuildContext context, Widget? child) =>
              overlay(bridge(child!)),
          home: const Text('app'),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('the pose matrix example iterates', () {
    for (final MapEntry<String, FoldInfo> entry
        in FoldInfoFakes.poseMatrix(size).entries) {
      expect(entry.value, isA<FoldInfo>());
    }
    expect(FoldInfoFakes.unsupported, FoldInfo.unsupported);
    expect(FoldInfoFakes.partiallyOpenVertical(viewSize: size), isNotNull);
  });
  // These used to be `expect(someTearOff, isNotNull)`, which no change to the
  // package could ever break -- a top-level function is never null. Their only
  // real effect was to compile the examples, which `flutter analyze` already
  // does. Calling them is what actually exercises the API the README promises.
  testWidgets('the capability gate example renders each branch', (
    tester,
  ) async {
    for (final profile in <BifoldCapabilities>[
      BifoldCapabilityFakes.book(),
      BifoldCapabilityFakes.flat,
      BifoldCapabilityFakes.unresolved,
    ]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: BifoldScope.fake(
            info: FoldInfoFakes.closed,
            capabilities: profile,
            child: Builder(builder: capabilityGate),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(Text), findsOneWidget);
    }
  });

  test('the capabilities-outside-the-tree example runs', () async {
    final platform = FakeBifoldPlatform(
      capabilities: BifoldCapabilityFakes.book(),
    );
    BifoldPlatform.instance = platform;
    addTearDown(platform.dispose);
    addTearDown(Bifold.debugReset);
    Bifold.debugReset();

    // Really invoked, so diagnosticReport() and sourceOf() are executed
    // rather than merely compiled.
    await capabilitiesOutsideTheTree();

    final report = await Bifold.diagnosticReport();
    expect(report, contains('bifold diagnostic report'));
    expect(report, contains('Capabilities'));
    expect(report, contains('fold'));
  });

  testWidgets('the fake-with-capabilities example mounts', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: fakeWithCapabilities(),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the drive-the-stream example reaches the tree', (tester) async {
    // This one used to be unreachable by construction, which hid a real bug:
    // it called addTearDown outside a test body, so invoking it threw.
    final platform = FakeBifoldPlatform();
    BifoldPlatform.instance = platform;
    addTearDown(platform.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: BifoldScope(
          child: Builder(
            builder: (context) => Text(Bifold.of(context).pose.name),
          ),
        ),
      ),
    );
    await tester.pump();

    platform.emit(FoldInfoFakes.partiallyOpen(viewSize: size));
    // The fake's stream is a broadcast controller, so delivery is a microtask
    // behind the emit. One pump drains it, the next rebuilds.
    await tester.pump();
    await tester.pump();
    expect(find.text('partiallyOpen'), findsOneWidget);
  });

  testWidgets('the rear-display example compiles and mounts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BifoldScope.fake(
          info: FoldInfoFakes.fullyOpen(viewSize: size),
          capabilities: BifoldCapabilityFakes.book(rearDisplay: true),
          // Switch needs a Material ancestor.
          child: Scaffold(body: Builder(builder: rearDisplayControl)),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

// --- The other display ----------------------------------------------------
Widget rearDisplayControl(BuildContext context) {
  final can = Bifold.capabilitiesOf(context);
  if (!can.hasRearDisplay) {
    return const SizedBox.shrink();
  }
  return StreamBuilder<RearDisplayAvailability>(
    stream: BifoldRearDisplay.availability,
    initialData: RearDisplayAvailability.unresolved,
    builder: (context, snapshot) {
      final now = snapshot.data ?? RearDisplayAvailability.unresolved;
      final running = now.presentation == RearDisplayStatus.active;
      return Switch(
        value: running,
        onChanged: now.presentation == RearDisplayStatus.available || running
            ? (on) => on
                ? BifoldRearDisplay.present(entrypoint: 'rearDisplayMain')
                : BifoldRearDisplay.end()
            : null,
      );
    },
  );
}

// --- What can this device do? --------------------------------------------
Widget capabilityGate(BuildContext context) {
  final can = Bifold.capabilitiesOf(context);
  if (can.hasHingeAngle) {
    return const Text('reacts to the angle');
  }
  switch (can.statusOf(FoldFeature.halfOpenedPosture)) {
    case CapabilityStatus.supported:
      return const Text('proven yes');
    case CapabilityStatus.unsupported:
      return const Text('proven no');
    case CapabilityStatus.unknown:
      return const Text('nobody has said');
  }
}

Future<void> capabilitiesOutsideTheTree() async {
  await Bifold.capabilitiesReady;
  // ignore: unused_local_variable
  final folds = Bifold.capabilities.hasFold;
  // ignore: unused_local_variable
  final source = Bifold.capabilities.sourceOf(FoldFeature.fold);
  // ignore: unused_local_variable
  final report = await Bifold.diagnosticReport();
}

// --- Testing -------------------------------------------------------------
Widget fakeWithCapabilities() => BifoldScope.fake(
      info: FoldInfoFakes.closed,
      capabilities: BifoldCapabilityFakes.unopenedFoldable(),
      child: const SizedBox(),
    );

// The README's snippet, kept verbatim apart from taking the platform as an
// argument: the original called addTearDown here, outside any test body, so
// it would have thrown if anything had ever run it.
void driveTheStream(FakeBifoldPlatform platform) {
  BifoldPlatform.instance = platform;
  platform.emit(FoldInfoFakes.partiallyOpen(viewSize: const Size(800, 1000)));
}
