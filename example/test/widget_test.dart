// Widget tests for the example app.
//
// These demonstrate the point of FoldInfoFakes: the example's reader is
// exercised across every pose without a simulator, an iOS SDK, or a device.

import 'package:bifold/bifold.dart';
import 'package:bifold_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Size kViewSize = Size(800, 1000);

void main() {
  Future<void> pumpReader(WidgetTester tester, FoldInfo info) async {
    tester.view
      ..physicalSize = kViewSize
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BifoldScope.fake(
        info: info,
        child: MaterialApp(
          home: ReaderPage(overlayEnabled: false, onToggleOverlay: () {}),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the reader lays out in every pose', (tester) async {
    for (final entry in FoldInfoFakes.poseMatrix(kViewSize).entries) {
      await pumpReader(tester, entry.value);

      expect(
        tester.takeException(),
        isNull,
        reason: 'threw while laid out as ${entry.key}',
      );
      // Both pages survive every pose; only their placement changes.
      expect(
        find.text('Page 1'),
        findsOneWidget,
        reason: 'page 1 missing as ${entry.key}',
      );
      expect(
        find.text('Page 2'),
        findsOneWidget,
        reason: 'page 2 missing as ${entry.key}',
      );
    }
  });

  testWidgets('the pages separate across an active crease', (tester) async {
    await pumpReader(
      tester,
      FoldInfoFakes.partiallyOpen(viewSize: kViewSize, thickness: 24),
    );

    final page1 = tester.getRect(find.text('Page 1'));
    final page2 = tester.getRect(find.text('Page 2'));

    // Page 2 begins below the crease, not immediately after page 1.
    expect(page2.top, greaterThan(page1.bottom + 24));
  });

  testWidgets('the status bar reports the live state', (tester) async {
    await pumpReader(tester, FoldInfo.unsupported);
    expect(find.text('not foldable'), findsOneWidget);
    expect(find.text('no active division'), findsOneWidget);

    await pumpReader(
      tester,
      FoldInfoFakes.partiallyOpen(viewSize: kViewSize),
    );
    expect(find.text('foldable'), findsOneWidget);
    expect(find.text('division active'), findsOneWidget);
    expect(find.text('pose: partiallyOpen'), findsOneWidget);
  });
}
