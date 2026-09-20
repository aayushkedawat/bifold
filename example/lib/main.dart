import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';

/// Content the system may show on the outer display during camera capture.
///
/// Runs in its own Flutter engine, so it is a separate entrypoint. The pragma
/// keeps it from being tree-shaken out of a release build.
@pragma('vm:entry-point')
void captureAccessoryMain() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: Color(0xFF101014),
        child: Center(
          child: Text(
            'You are on camera',
            textDirection: TextDirection.ltr,
            style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 20),
          ),
        ),
      ),
    ),
  );
}

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
  bool _overlayEnabled = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'bifold example',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3D5AFE),
        brightness: Brightness.dark,
      ),
      // The overlay wraps the whole app so it draws over the Scaffold too,
      // including the area behind the app bar where the camera cutout sits.
      builder: (context, child) => BifoldDebugOverlay(
        enabled: _overlayEnabled,
        child: child!,
      ),
      home: ReaderPage(
        overlayEnabled: _overlayEnabled,
        onToggleOverlay: () =>
            setState(() => _overlayEnabled = !_overlayEnabled),
      ),
    );
  }
}

/// A two-page reader that splits across the fold.
class ReaderPage extends StatelessWidget {
  const ReaderPage({
    required this.overlayEnabled,
    required this.onToggleOverlay,
    super.key,
  });

  final bool overlayEnabled;
  final VoidCallback onToggleOverlay;

  @override
  Widget build(BuildContext context) {
    final info = Bifold.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('bifold'),
        actions: <Widget>[
          IconButton(
            tooltip: overlayEnabled ? 'Hide regions' : 'Show regions',
            onPressed: onToggleOverlay,
            icon: Icon(
              overlayEnabled ? Icons.grid_off : Icons.grid_on,
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _StatusBar(info: info),
          Expanded(
            child: BifoldSplit(
              start: const _Page(
                number: 1,
                title: 'On folding',
                body:
                    'The panes above and below this line are placed clear of '
                    'the crease and its margins. Fold the device part-way to '
                    'see them separate.',
              ),
              end: const _Page(
                number: 2,
                title: 'On falling back',
                body:
                    'When there is no active division — flat, shut, or on a '
                    'phone that does not fold — the two pages stack instead. '
                    'Nothing throws and nothing is hidden.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live read-out of what the platform is reporting.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.info});

  final FoldInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final division = info.division;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.surfaceContainerHighest,
      child: DefaultTextStyle(
        style: theme.textTheme.bodySmall!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                _Chip(
                  label: info.isFoldable ? 'foldable' : 'not foldable',
                  highlight: info.isFoldable,
                ),
                _Chip(label: 'display: ${info.display.name}'),
                _Chip(label: 'pose: ${info.pose.name}'),
                if (info.hingeAngleDegrees case final degrees?)
                  _Chip(label: '${degrees.toStringAsFixed(0)}\u00b0'),
                _Chip(
                  label: '${info.regions.length} region'
                      '${info.regions.length == 1 ? '' : 's'}',
                ),
                _Chip(
                  label: 'size: ${info.horizontalSizeClass.name}/'
                      '${info.verticalSizeClass.name}',
                ),
                if (info.verticalBarEdge != VerticalBarEdge.unspecified)
                  _Chip(label: 'bar: ${info.verticalBarEdge.name}'),
                _Chip(
                  label: division == null
                      ? 'no active division'
                      : 'division active',
                  highlight: division != null,
                ),
              ],
            ),
            if (!info.isFoldable) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'This device reports no fold. Everything below still lays out '
                'and nothing throws.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.highlight = false});

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

class _Page extends StatelessWidget {
  const _Page({
    required this.number,
    required this.title,
    required this.body,
  });

  final int number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Page $number',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Text(body, style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}
