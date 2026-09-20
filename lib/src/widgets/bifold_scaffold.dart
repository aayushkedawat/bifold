import 'package:flutter/material.dart';

import '../models.dart';
import 'bifold_scope.dart';

/// One navigation target in a [BifoldScaffold].
@immutable
class BifoldDestination {
  /// Creates a destination.
  const BifoldDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  /// Shown when the destination is not selected.
  final Widget icon;

  /// Shown when it is selected. Falls back to [icon].
  final Widget? selectedIcon;

  /// The destination's name.
  final String label;
}

/// A scaffold that moves its navigation as the device folds.
///
/// On a compact layout — the outer display, or any ordinary phone — this is a
/// [Scaffold] with a [NavigationBar] along the bottom. On a regular layout,
/// which is what the inner display reports, the navigation becomes a
/// [NavigationRail] down the side.
///
/// The side is not guessed. The platform publishes which edge it prefers for
/// its own vertical bar, and this places the rail to match, so app navigation
/// and system UI end up on the same side rather than sandwiching the content:
///
/// ```dart
/// BifoldScaffold(
///   appBar: AppBar(title: const Text('Inbox')),
///   selectedIndex: index,
///   onDestinationSelected: (i) => setState(() => index = i),
///   destinations: const <BifoldDestination>[
///     BifoldDestination(icon: Icon(Icons.inbox), label: 'Inbox'),
///     BifoldDestination(icon: Icon(Icons.send), label: 'Sent'),
///   ],
///   body: const MessageList(),
/// )
/// ```
///
/// With fewer than two destinations the navigation is omitted entirely rather
/// than rendered as a single useless item.
///
/// Everything degrades: on a device with no fold this is an ordinary scaffold
/// with a bottom bar, which is what such a device should have anyway.
class BifoldScaffold extends StatelessWidget {
  /// Creates a fold-aware scaffold.
  const BifoldScaffold({
    required this.body,
    this.destinations = const <BifoldDestination>[],
    this.selectedIndex = 0,
    this.onDestinationSelected,
    this.appBar,
    this.floatingActionButton,
    this.backgroundColor,
    this.railLeading,
    super.key,
  });

  /// The main content.
  final Widget body;

  /// Navigation targets. Fewer than two omits the navigation.
  final List<BifoldDestination> destinations;

  /// Which destination is selected.
  final int selectedIndex;

  /// Called when a destination is chosen.
  final ValueChanged<int>? onDestinationSelected;

  /// An optional app bar, passed through to [Scaffold].
  final PreferredSizeWidget? appBar;

  /// An optional floating action button, passed through to [Scaffold].
  final Widget? floatingActionButton;

  /// Background colour, passed through to [Scaffold].
  final Color? backgroundColor;

  /// Shown at the top of the rail, above the destinations.
  ///
  /// Ignored in the compact layout, where there is no rail.
  final Widget? railLeading;

  @override
  Widget build(BuildContext context) {
    final FoldInfo info = Bifold.of(context);
    final bool hasNavigation = destinations.length > 1;

    if (!info.isRegular || !hasNavigation) {
      return Scaffold(
        appBar: appBar,
        backgroundColor: backgroundColor,
        floatingActionButton: floatingActionButton,
        body: body,
        bottomNavigationBar: hasNavigation
            ? NavigationBar(
                selectedIndex: _clampedIndex,
                onDestinationSelected: onDestinationSelected,
                destinations: <Widget>[
                  for (final BifoldDestination destination in destinations)
                    NavigationDestination(
                      icon: destination.icon,
                      selectedIcon: destination.selectedIcon,
                      label: destination.label,
                    ),
                ],
              )
            : null,
      );
    }

    final Widget rail = NavigationRail(
      selectedIndex: _clampedIndex,
      onDestinationSelected: onDestinationSelected,
      labelType: NavigationRailLabelType.all,
      leading: railLeading,
      destinations: <NavigationRailDestination>[
        for (final BifoldDestination destination in destinations)
          NavigationRailDestination(
            icon: destination.icon,
            selectedIcon: destination.selectedIcon,
            label: Text(destination.label),
          ),
      ],
    );

    // Put the rail on the edge the system prefers for its vertical bar, so app
    // navigation and system UI share a side instead of bracketing the content.
    final bool onTrailing = info.verticalBarEdge == VerticalBarEdge.trailing;
    final List<Widget> row = <Widget>[
      rail,
      const VerticalDivider(thickness: 1, width: 1),
      Expanded(child: body),
    ];

    return Scaffold(
      appBar: appBar,
      backgroundColor: backgroundColor,
      floatingActionButton: floatingActionButton,
      body: Row(
        children: onTrailing ? row.reversed.toList() : row,
      ),
    );
  }

  /// Guards against a selected index outside the destination list.
  ///
  /// A caller that shortens [destinations] without resetting [selectedIndex]
  /// would otherwise throw from inside the navigation widget.
  int get _clampedIndex =>
      destinations.isEmpty ? 0 : selectedIndex.clamp(0, destinations.length - 1);
}
