// Asks UIKit where it would place two panes, and prints the answer.
//
// The reserved-region query returns nothing on this simulator, so this is the
// other route to real, system-produced split geometry.

import 'package:bifold/bifold.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('measure UIKit split arrangement', (tester) async {
    const channel = MethodChannel('dev.bifold/methods');
    final info = await Bifold.current;

    final buffer = StringBuffer('\n>>>>>>>>>> BIFOLD ARRANGEMENT\n')
      ..writeln('pose: ${info.pose.name}  regions: ${info.regions.length}');

    for (final axis in <String>['horizontal', 'vertical']) {
      for (final size in <List<double>>[
        <double>[871, 669],
        <double>[800, 1000],
      ]) {
        Object? measured;
        try {
          measured = await channel.invokeMethod<Map<Object?, Object?>>(
            'measureArrangement',
            <String, Object?>{
              'width': size[0],
              'height': size[1],
              'axis': axis,
            },
          );
        } on PlatformException catch (e) {
          measured = 'ERROR $e';
        }
        buffer.writeln('$axis ${size[0]}x${size[1]} -> $measured');
      }
    }
    await channel.invokeMethod<void>('releaseArrangement');
    buffer.writeln('<<<<<<<<<< BIFOLD ARRANGEMENT END');
    // ignore: avoid_print
    print(buffer.toString());

    expect(tester.takeException(), isNull);
  });
}
