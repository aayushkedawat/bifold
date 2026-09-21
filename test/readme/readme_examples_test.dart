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
  test('the capability examples build', () {
    expect(capabilityGate, isNotNull);
    expect(capabilitiesOutsideTheTree, isNotNull);
  });
  test('the testing examples build', () {
    expect(fakeWithCapabilities, isNotNull);
    expect(driveTheStream, isNotNull);
  });
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

void driveTheStream(WidgetTester tester) {
  final platform = FakeBifoldPlatform();
  BifoldPlatform.instance = platform;
  addTearDown(platform.dispose);
  platform.emit(FoldInfoFakes.partiallyOpen(viewSize: const Size(800, 1000)));
}
