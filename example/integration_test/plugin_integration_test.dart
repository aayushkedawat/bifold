// Integration tests that run against a real device or simulator.
//
// Run with:
//   cd example && flutter test integration_test
//
// On a device without a fold these assert the degraded contract: a
// well-defined "no fold" state, and never an exception.

import 'package:bifold/bifold.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reading fold state never throws', (tester) async {
    final info = await Bifold.current;

    // Whatever the device, the result is a usable value.
    expect(info.regions, isNotNull);
    if (!info.isFoldable) {
      expect(info.display, FoldDisplay.none);
      expect(info.pose, FoldPose.unknown);
      expect(info.regions, isEmpty);
      expect(info.division, isNull);
    }
  });

  testWidgets('the fold stream emits a first value promptly', (tester) async {
    // The native side emits immediately on listen rather than waiting for the
    // first change, so an app never sits on an empty stream.
    final info = await Bifold.stream.first.timeout(const Duration(seconds: 5));
    expect(info, isNotNull);
  });

  testWidgets('regions are consistent with the reported pose', (tester) async {
    final info = await Bifold.current;

    if (info.pose == FoldPose.closed) {
      // The outer display reports no reserved regions at all.
      expect(info.regions, isEmpty, reason: 'closed device reported regions');
    }
    if (info.pose != FoldPose.partiallyOpen) {
      // A division is only active while the display is creased.
      expect(
        info.division,
        isNull,
        reason: 'active division reported while ${info.pose.name}',
      );
    }
  });
}
