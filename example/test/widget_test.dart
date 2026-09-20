// Widget tests for the example app.
//
// These demonstrate the point of FoldInfoFakes: every demo page is exercised
// across every pose without a simulator, an iOS SDK, or a device.

import 'package:bifold/bifold.dart';
import 'package:bifold_example/main.dart';
import 'package:bifold_example/pages/gallery_page.dart';
import 'package:bifold_example/pages/inspector_page.dart';
import 'package:bifold_example/pages/reader_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Size kViewSize = Size(900, 1200);

void main() {
  Future<void> pump(WidgetTester tester, Widget page, FoldInfo info) async {
    tester.view
      ..physicalSize = kViewSize
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BifoldScope.fake(
        info: info,
        child: MaterialApp(home: Scaffold(body: page)),
      ),
    );
    await tester.pump();
  }

  group('every demo page survives every pose', () {
    final pages = <String, Widget Function()>{
      'reader': ReaderPage.new,
      'gallery': GalleryPage.new,
      'inspector': InspectorPage.new,
    };

    for (final entry in pages.entries) {
      testWidgets('${entry.key} lays out in every pose', (tester) async {
        for (final pose in FoldInfoFakes.poseMatrix(kViewSize).entries) {
          await pump(tester, entry.value(), pose.value);
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} threw while laid out as ${pose.key}',
          );
        }
      });
    }
  });

  group('reader', () {
    testWidgets('separates the pages across an active crease', (tester) async {
      await pump(
        tester,
        const ReaderPage(),
        FoldInfoFakes.partiallyOpen(viewSize: kViewSize, thickness: 24),
      );

      final page1 = tester.getRect(find.text('Page 1'));
      final page2 = tester.getRect(find.text('Page 2'));
      expect(page2.top, greaterThan(page1.bottom + 24));
    });

    testWidgets('stacks the pages when flat', (tester) async {
      await pump(
        tester,
        const ReaderPage(),
        FoldInfoFakes.fullyOpen(viewSize: kViewSize),
      );
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsOneWidget);
    });
  });

  group('inspector', () {
    testWidgets('reports the live values', (tester) async {
      await pump(
        tester,
        const InspectorPage(),
        FoldInfoFakes.partiallyOpen(viewSize: kViewSize),
      );

      expect(find.text('partiallyOpen'), findsOneWidget);
      expect(find.text('inner'), findsOneWidget);
      expect(find.textContaining('Regions (2)'), findsOneWidget);
    });

    testWidgets('explains an empty region list rather than showing nothing',
        (tester) async {
      await pump(tester, const InspectorPage(), FoldInfoFakes.closed);
      expect(find.textContaining('No reserved regions'), findsOneWidget);
    });
  });

  group('navigation adapts to the size class', () {
    testWidgets('a rail on the inner display, a bar on the outer',
        (tester) async {
      tester.view
        ..physicalSize = kViewSize
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Future<void> pumpHome(FoldInfo info) async {
        await tester.pumpWidget(
          BifoldScope.fake(
            info: info,
            child: MaterialApp(
              home: HomePage(
                overlayEnabled: false,
                bridgeEnabled: false,
                onToggleOverlay: () {},
                onToggleBridge: () {},
              ),
            ),
          ),
        );
        await tester.pump();
      }

      // Inner display: regular in both axes. BifoldScaffold puts the
      // navigation in a rail there.
      await pumpHome(
        FoldInfoFakes.partiallyOpen(viewSize: kViewSize).copyWith(
          horizontalSizeClass: FoldSizeClass.regular,
          verticalSizeClass: FoldSizeClass.regular,
        ),
      );
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      // Outer display: compact. Navigation must not vanish.
      await pumpHome(
        FoldInfoFakes.closed.copyWith(
          horizontalSizeClass: FoldSizeClass.compact,
        ),
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });
  });

  group('status bar', () {
    testWidgets('reports the live state', (tester) async {
      await pump(
        tester,
        StatusBar(info: FoldInfoFakes.partiallyOpen(viewSize: kViewSize)),
        FoldInfoFakes.partiallyOpen(viewSize: kViewSize),
      );

      expect(find.text('foldable'), findsOneWidget);
      expect(find.text('division active'), findsOneWidget);
      expect(find.text('pose: partiallyOpen'), findsOneWidget);
      expect(find.text('90°'), findsOneWidget);
    });

    testWidgets('says plainly when there is no fold', (tester) async {
      await pump(
        tester,
        const StatusBar(info: FoldInfo.unsupported),
        FoldInfo.unsupported,
      );
      expect(find.text('not foldable'), findsOneWidget);
      expect(find.text('no active division'), findsOneWidget);
    });
  });
}
