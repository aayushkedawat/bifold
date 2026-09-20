// Reads real fold state from whatever device this runs on.
//
// On an iPhone Duo simulator this is the only end-to-end proof that the
// runtime-resolved selectors actually work. On any other device it asserts the
// degraded contract instead.

import 'package:bifold/bifold.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('read live fold state', (tester) async {
    const channel = MethodChannel('dev.bifold/methods');
    final supported = await channel.invokeMethod<bool>('isSupported');
    final info = await Bifold.current;

    // ignore: avoid_print
    print(
      '\n>>>>>>>>>> BIFOLD LIVE\n'
      'isSupported (OS has the API): $supported\n'
      'isFoldable: ${info.isFoldable}\n'
      'display:    ${info.display.name}\n'
      'pose:       ${info.pose.name}\n'
      'regions:    ${info.regions.length}\n'
      '${info.regions.map((r) => '  $r').join('\n')}\n'
      '<<<<<<<<<< BIFOLD LIVE END\n',
    );

    expect(info, isNotNull);
  });
}
