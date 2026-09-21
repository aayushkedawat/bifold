import 'package:bifold/bifold.dart';
import 'package:bifold_example/downstream/hinge_creature.dart';
import 'package:bifold_example/downstream/rear_display_camera.dart';
import 'package:bifold_example/downstream/two_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the downstream examples behave on every device shape, using only
/// fakes: no simulator, no emulator, no platform channel.
void main() {
  Widget wrap(Widget child, FoldInfo info, [BifoldCapabilities? caps]) =>
      MaterialApp(
        home: BifoldScope.fake(
          info: info,
          capabilities: caps,
          // Scaffold rather than a bare child: the list tiles in example C
          // need a Material ancestor, and the camera fills its column.
          child: Scaffold(body: child),
        ),
      );

  group('A. hinge creature', () {
    testWidgets('sleeps on a device proven not to fold', (tester) async {
      await tester.pumpWidget(
        wrap(const HingeCreature(), FoldInfo.none, BifoldCapabilities.none),
      );
      expect(find.text('asleep'), findsOneWidget);
    });

    testWidgets('waits rather than guessing before the platform answers', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const HingeCreature(),
          FoldInfo.unsupported,
          BifoldCapabilities.unresolved,
        ),
      );
      // The bug this catches: treating an unresolved capability as a "no"
      // makes the creature fall asleep for a frame on a real foldable.
      expect(find.text('asleep'), findsNothing);
      expect(find.text('waking'), findsOneWidget);
    });

    testWidgets('watches the angle when there is one', (tester) async {
      await tester.pumpWidget(
        wrap(
          const HingeCreature(),
          FoldInfoFakes.partiallyOpen(viewSize: const Size(800, 1000)),
          BifoldCapabilityFakes.book(),
        ),
      );
      expect(find.text('watching'), findsOneWidget);
    });

    testWidgets('falls back to pose when the sensor is silent', (tester) async {
      final silent = FoldInfoFakes.partiallyOpen(
        viewSize: const Size(800, 1000),
      ).copyWith(clearHingeAngle: true);
      await tester.pumpWidget(
        wrap(const HingeCreature(), silent, BifoldCapabilityFakes.book()),
      );
      expect(find.text('peeking'), findsOneWidget);
    });
  });

  group('B. two pane', () {
    Widget panes() => const TwoPane(start: Text('list'), end: Text('detail'));

    testWidgets('stacks on an ordinary phone', (tester) async {
      await tester.pumpWidget(wrap(panes(), FoldInfo.none));
      expect(find.text('list'), findsOneWidget);
      expect(find.text('detail'), findsOneWidget);
    });

    testWidgets('splits across an active fold', (tester) async {
      await tester.pumpWidget(
        wrap(
          panes(),
          FoldInfoFakes.partiallyOpen(viewSize: const Size(800, 1000)),
        ),
      );
      expect(find.text('list'), findsOneWidget);
      expect(find.text('detail'), findsOneWidget);
    });

    testWidgets('keeps both panes when flat and roomy', (tester) async {
      await tester.pumpWidget(
        wrap(
          panes(),
          FoldInfoFakes.fullyOpen(viewSize: const Size(800, 1000)).copyWith(
            horizontalSizeClass: FoldSizeClass.regular,
            verticalSizeClass: FoldSizeClass.regular,
          ),
        ),
      );
      expect(find.text('detail'), findsOneWidget);
    });
  });

  group('C. rear display camera', () {
    testWidgets('offers nothing on a device proven not to have one', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const RearDisplayCamera(), FoldInfo.none, BifoldCapabilities.none),
      );
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.textContaining('Checking'), findsNothing);
    });

    testWidgets('says it is still checking while unknown', (tester) async {
      await tester.pumpWidget(
        wrap(
          const RearDisplayCamera(),
          FoldInfo.unsupported,
          BifoldCapabilityFakes.unopenedFoldable(),
        ),
      );
      expect(find.textContaining('Checking'), findsOneWidget);
    });

    testWidgets('shows a disabled control until the system is ready', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const RearDisplayCamera(),
          FoldInfoFakes.fullyOpen(viewSize: const Size(800, 1000)),
          BifoldCapabilityFakes.book(rearDisplay: true),
        ),
      );
      await tester.pump();
      expect(find.byType(SwitchListTile), findsOneWidget);
      final SwitchListTile tile = tester.widget(find.byType(SwitchListTile));
      // Capability yes, availability no: present but not operable.
      expect(tile.onChanged, isNull);
    });
  });
}
