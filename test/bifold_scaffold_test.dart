import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Size kViewSize = Size(900, 1200);

const List<BifoldDestination> kDestinations = <BifoldDestination>[
  BifoldDestination(icon: Icon(Icons.inbox), label: 'Inbox'),
  BifoldDestination(icon: Icon(Icons.send), label: 'Sent'),
];

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required FoldInfo info,
    List<BifoldDestination> destinations = kDestinations,
    int selectedIndex = 0,
  }) async {
    tester.view
      ..physicalSize = kViewSize
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BifoldScope.fake(
        info: info,
        child: MaterialApp(
          home: BifoldScaffold(
            destinations: destinations,
            selectedIndex: selectedIndex,
            onDestinationSelected: (_) {},
            body: const SizedBox.expand(key: ValueKey<String>('body')),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  FoldInfo regular({VerticalBarEdge edge = VerticalBarEdge.unspecified}) =>
      FoldInfoFakes.fullyOpen(viewSize: kViewSize).copyWith(
        horizontalSizeClass: FoldSizeClass.regular,
        verticalSizeClass: FoldSizeClass.regular,
        verticalBarEdge: edge,
      );

  testWidgets('a bar when compact, a rail when regular', (tester) async {
    await pump(
      tester,
      info: FoldInfoFakes.closed.copyWith(
        horizontalSizeClass: FoldSizeClass.compact,
      ),
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await pump(tester, info: regular());
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('the rail follows the system vertical bar edge', (tester) async {
    await pump(tester, info: regular(edge: VerticalBarEdge.leading));
    final leading = tester.getRect(find.byType(NavigationRail));
    final bodyLeading = tester.getRect(
      find.byKey(const ValueKey<String>('body')),
    );
    expect(
      leading.left,
      lessThan(bodyLeading.left),
      reason: 'leading edge should put the rail before the body',
    );

    await pump(tester, info: regular(edge: VerticalBarEdge.trailing));
    final trailing = tester.getRect(find.byType(NavigationRail));
    final bodyTrailing = tester.getRect(
      find.byKey(const ValueKey<String>('body')),
    );
    expect(
      trailing.left,
      greaterThan(bodyTrailing.left),
      reason: 'trailing edge should put the rail after the body',
    );
  });

  testWidgets('navigation is omitted below two destinations', (tester) async {
    // A single-item bar is worse than no bar.
    await pump(
      tester,
      info: regular(),
      destinations: const <BifoldDestination>[
        BifoldDestination(icon: Icon(Icons.inbox), label: 'Inbox'),
      ],
    );
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const ValueKey<String>('body')), findsOneWidget);
  });

  testWidgets('an out-of-range selection does not throw', (tester) async {
    // A caller that shortens the list without resetting the index would
    // otherwise assert from inside the navigation widget.
    await pump(tester, info: regular(), selectedIndex: 7);
    expect(tester.takeException(), isNull);

    await pump(
      tester,
      info: FoldInfoFakes.closed.copyWith(
        horizontalSizeClass: FoldSizeClass.compact,
      ),
      selectedIndex: 7,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the body survives every pose', (tester) async {
    for (final entry in FoldInfoFakes.poseMatrix(kViewSize).entries) {
      await pump(tester, info: entry.value);
      expect(
        tester.takeException(),
        isNull,
        reason: 'threw while laid out as ${entry.key}',
      );
      expect(find.byKey(const ValueKey<String>('body')), findsOneWidget);
    }
  });
}
