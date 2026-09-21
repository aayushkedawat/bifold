// Dumps the fold API surface of the running OS.
//
// Not an assertion suite: this exists to VERIFY the symbols that FoldReader
// resolves through the Objective-C runtime, by asking the runtime itself.
// Run it on an iPhone Duo simulator and reconcile the output with
// API_NOTES.md:
//
//   cd example
//   flutter test integration_test/native_api_probe_test.dart -d <duo-udid>

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dump the native fold API', (tester) async {
    const channel = MethodChannel('dev.bifold/methods');
    final dump = await channel.invokeMethod<String>('debugDescribeNativeApi');

    // ignore: avoid_print
    print(
      '\n>>>>>>>>>> BIFOLD PROBE START\n$dump\n<<<<<<<<<< BIFOLD PROBE END\n',
    );
    expect(dump, isNotNull);
  });
}
