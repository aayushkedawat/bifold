// Watches the fold stream long enough for the hinge to report.
//
// The hinge interaction is attached when the stream is listened to, and its
// first update arrives asynchronously, so a one-shot read cannot see it.

import 'package:bifold/bifold.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the stream reports hinge state', (tester) async {
    final seen = <FoldInfo>[];
    final sub = Bifold.stream.listen(seen.add);
    addTearDown(sub.cancel);

    // Give the hinge interaction time to deliver its initial update.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (seen.any((i) => i.hingeAngle != null)) break;
    }

    // ignore: avoid_print
    print(
      '\n>>>>>>>>>> BIFOLD STREAM\n'
      'events: ${seen.length}\n'
      '${seen.map((i) => '  $i').join('\n')}\n'
      '<<<<<<<<<< BIFOLD STREAM END\n',
    );

    expect(seen, isNotEmpty, reason: 'stream never emitted');
  });
}
