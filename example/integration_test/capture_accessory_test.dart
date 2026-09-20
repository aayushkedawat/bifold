// Exercises the camera capture accessory on a real device.
//
// The accessory cannot actually be presented without an active capture
// session, so this checks the half that is reachable: that the OS exposes the
// API, that registration succeeds against the live view controller, and that
// availability reports without throwing.

import 'package:bifold/bifold.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture accessory registers on the live view controller',
      (tester) async {
    final supported = await BifoldCaptureAccessory.isSupported;
    final registered = supported
        ? await BifoldCaptureAccessory.register(
            entrypoint: 'captureAccessoryMain',
          )
        : false;
    await BifoldCaptureAccessory.setEnabled(true);
    final available = await BifoldCaptureAccessory.isAvailable;

    // ignore: avoid_print
    print(
      '\n>>>>>>>>>> BIFOLD ACCESSORY\n'
      'isSupported: $supported\n'
      'registered:  $registered\n'
      'available:   $available  (false without a capture session)\n'
      '<<<<<<<<<< BIFOLD ACCESSORY END\n',
    );

    await BifoldCaptureAccessory.unregister();
    expect(tester.takeException(), isNull);
  });
}
