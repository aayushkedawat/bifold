// Exercises the rear display on a real device.
//
// A session cannot actually run on iOS without an active camera capture
// session, so this checks the half that is reachable on both platforms: that
// the status reports without throwing, that it distinguishes "unsupported"
// from "not established", and that asking to present and then ending is safe
// whatever the system decides.

import 'package:bifold/bifold.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rear display reports a status and survives a request', (
    tester,
  ) async {
    final capabilities = await Bifold.capabilitiesReady;
    final before = await BifoldRearDisplay.current;

    // Asking is safe even where it cannot work: false means the system said
    // no, which is a documented answer rather than an error.
    final presented = await BifoldRearDisplay.present(
      entrypoint: 'rearDisplayMain',
    );
    final during = await BifoldRearDisplay.current;
    await BifoldRearDisplay.end();
    final after = await BifoldRearDisplay.current;

    // ignore: avoid_print
    print(
      '\n>>>>>>>>>> BIFOLD REAR DISPLAY\n'
      'capability:  ${capabilities.statusOf(FoldFeature.rearDisplay).name}\n'
      'modes:       ${capabilities.rearDisplayModes.map((m) => m.name).join(', ')}\n'
      'before:      $before\n'
      'present():   $presented\n'
      'during:      $during\n'
      'after end(): $after\n'
      '<<<<<<<<<< BIFOLD REAR DISPLAY END\n',
    );

    // Whatever the platform decided, nothing may throw and the report must be
    // an answer rather than silence by the time capabilities have resolved.
    expect(tester.takeException(), isNull);
    expect(after.isResolved, isTrue);
  });
}
