import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';

import 'pages/capabilities_page.dart';
import 'pages/downstream_page.dart';
import 'pages/gallery_page.dart';
import 'pages/inspector_page.dart';
import 'pages/reader_page.dart';
import 'pages/studio_page.dart';
import 'widgets/hinge_gauge.dart';

/// Content the system may show on the outer display during camera capture.
///
/// This runs in its own Flutter engine, so it is a separate entrypoint. The
/// pragma keeps it from being tree-shaken out of a release build.
@pragma('vm:entry-point')
void captureAccessoryMain() => runApp(const SubjectView());

void main() {
  // One scope at the root. Everything below it can read fold state.
  runApp(const BifoldScope(child: ExampleApp()));
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  bool _overlay = true;
  bool _bridgeDisplayFeatures = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'bifold',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3D5AFE),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      builder: (context, child) {
        // Republish the fold as MediaQuery.displayFeatures, so Flutter's own
        // dialog positioning and any Android-foldable package see it too.
        Widget content = child!;
        if (_bridgeDisplayFeatures) {
          content = BifoldDisplayFeatures(child: content);
        }
        // The overlay wraps everything so it draws over the Scaffold as well,
        // including the area behind the app bar where a cutout sits.
        return BifoldDebugOverlay(enabled: _overlay, child: content);
      },
      home: HomePage(
        overlayEnabled: _overlay,
        bridgeEnabled: _bridgeDisplayFeatures,
        onToggleOverlay: () => setState(() => _overlay = !_overlay),
        onToggleBridge: () =>
            setState(() => _bridgeDisplayFeatures = !_bridgeDisplayFeatures),
      ),
    );
  }
}

/// Hosts the demos, with a live read-out of fold state above them.
class HomePage extends StatefulWidget {
  const HomePage({
    required this.overlayEnabled,
    required this.bridgeEnabled,
    required this.onToggleOverlay,
    required this.onToggleBridge,
    super.key,
  });

  final bool overlayEnabled;
  final bool bridgeEnabled;
  final VoidCallback onToggleOverlay;
  final VoidCallback onToggleBridge;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  static const List<_Demo> _demos = <_Demo>[
    _Demo('Reader', Icons.menu_book_outlined, ReaderPage()),
    _Demo('Gallery', Icons.grid_view_outlined, GalleryPage()),
    _Demo('Studio', Icons.videocam_outlined, StudioPage()),
    _Demo('Inspector', Icons.science_outlined, InspectorPage()),
    _Demo('Can do', Icons.checklist_outlined, CapabilitiesPage()),
    _Demo('Apps', Icons.apps_outlined, DownstreamPage()),
  ];

  @override
  Widget build(BuildContext context) {
    return BifoldScaffold(
      appBar: AppBar(
        title: const Text('bifold'),
        actions: <Widget>[
          IconButton(
            tooltip: widget.bridgeEnabled
                ? 'displayFeatures bridge on'
                : 'displayFeatures bridge off',
            onPressed: widget.onToggleBridge,
            icon: Icon(widget.bridgeEnabled ? Icons.link : Icons.link_off),
          ),
          IconButton(
            tooltip: widget.overlayEnabled ? 'Hide regions' : 'Show regions',
            onPressed: widget.onToggleOverlay,
            icon: Icon(widget.overlayEnabled ? Icons.grid_off : Icons.grid_on),
          ),
        ],
      ),
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: <BifoldDestination>[
        for (final demo in _demos)
          BifoldDestination(icon: Icon(demo.icon), label: demo.label),
      ],
      body: Column(
        children: <Widget>[
          const _LiveHingeGauge(),
          const _LiveStatusBar(),
          Expanded(child: _demos[_tab].page),
        ],
      ),
    );
  }
}

/// Reads fold state itself, so the scaffold above it does not have to.
class _LiveStatusBar extends StatelessWidget {
  const _LiveStatusBar();

  @override
  Widget build(BuildContext context) => StatusBar(info: Bifold.of(context));
}

/// The hinge read-out, kept above the tabs so it stays on screen throughout.
class _LiveHingeGauge extends StatelessWidget {
  const _LiveHingeGauge();

  @override
  Widget build(BuildContext context) => HingeGauge(info: Bifold.of(context));
}

class _Demo {
  const _Demo(this.label, this.icon, this.page);
  final String label;
  final IconData icon;
  final Widget page;
}

/// Live read-out of everything `FoldInfo` exposes.
class StatusBar extends StatelessWidget {
  const StatusBar({required this.info, super.key});

  final FoldInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              Chip2(
                label: info.isFoldable ? 'foldable' : 'not foldable',
                highlight: info.isFoldable,
              ),
              Chip2(label: 'display: ${info.display.name}'),
              Chip2(label: 'pose: ${info.pose.name}'),
              Chip2(
                label:
                    'size: ${info.horizontalSizeClass.name}/'
                    '${info.verticalSizeClass.name}',
              ),
              if (info.verticalBarEdge != VerticalBarEdge.unspecified)
                Chip2(label: 'bar: ${info.verticalBarEdge.name}'),
              Chip2(
                label:
                    '${info.regions.length} region'
                    '${info.regions.length == 1 ? '' : 's'}',
              ),
              Chip2(
                label: info.division == null
                    ? 'no active division'
                    : 'division active',
                highlight: info.division != null,
              ),
            ],
          ),
          if (!info.isFoldable) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'This device reports no fold. Every demo below still lays out '
              'and nothing throws.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact pill, small enough that a dozen fit on the outer display.
class Chip2 extends StatelessWidget {
  const Chip2({required this.label, this.highlight = false, super.key});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight ? scheme.primary : scheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: highlight ? scheme.onPrimary : scheme.onSurface,
        ),
      ),
    );
  }
}

/// What the person in front of the camera sees on the outer display.
///
/// A separate engine renders this, so it shares no state with the main app —
/// which is why it is a plain, self-contained widget.
class SubjectView extends StatelessWidget {
  const SubjectView({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: Color(0xFF0B0B0F),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.fiber_manual_record,
                  color: Color(0xFFFF5252),
                  size: 40,
                ),
                SizedBox(height: 12),
                Text(
                  'You are on camera',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Look here',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
