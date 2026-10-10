import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';

/// How to read fold state without rebuilding the world.
///
/// Every card below counts its own builds. Fold the device, or inject a hinge
/// angle, and watch which counters move: `Bifold.of` climbs with every update,
/// while the scoped accessors sit still until the aspect they asked for
/// actually changes. On a hinge streaming at sensor rate that is the
/// difference between one rebuild and hundreds.
///
/// This page deliberately reads nothing itself. An ancestor that calls
/// `Bifold.of` would rebuild the whole subtree on every update and the
/// counters would all climb together, which is exactly the mistake the
/// scoped accessors exist to prevent.
class ReadsPage extends StatefulWidget {
  /// Creates the page.
  const ReadsPage({super.key});

  @override
  State<ReadsPage> createState() => _ReadsPageState();
}

class _ReadsPageState extends State<ReadsPage> {
  /// Bumped to give every card fresh state, which zeroes the counts.
  int _generation = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('Scoped reads', style: theme.textTheme.titleMedium),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _generation++),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset counts'),
            ),
          ],
        ),
        Text(
          'Each card watches one aspect and counts its own builds.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _Counter(
          key: ValueKey<String>('of-$_generation'),
          call: 'Bifold.of(context)',
          note: 'The whole FoldInfo. Rebuilds on any change at all.',
          read: (context) {
            final info = Bifold.of(context);
            return '${info.pose.name}, '
                '${info.hingeAngleDegrees?.toStringAsFixed(0) ?? '--'}°';
          },
        ),
        _Counter(
          key: ValueKey<String>('pose-$_generation'),
          call: 'Bifold.poseOf(context)',
          note: 'Still while the angle moves within a pose.',
          read: (context) => Bifold.poseOf(context).name,
        ),
        _Counter(
          key: ValueKey<String>('angle-$_generation'),
          call: 'Bifold.hingeAngleOf(context)',
          note: 'Radians, null where there is no valid reading.',
          read: (context) =>
              Bifold.hingeAngleOf(context)?.toStringAsFixed(3) ?? 'null',
        ),
        _Counter(
          key: ValueKey<String>('display-$_generation'),
          call: 'Bifold.displayOf(context)',
          note: 'Changes when the app moves between inner and outer.',
          read: (context) => Bifold.displayOf(context).name,
        ),
        _Counter(
          key: ValueKey<String>('regions-$_generation'),
          call: 'Bifold.regionsOf(context)',
          note: 'The reserved regions, crease and cutout.',
          read: (context) => '${Bifold.regionsOf(context).length} region(s)',
        ),
        _Counter(
          key: ValueKey<String>('capabilities-$_generation'),
          call: 'Bifold.capabilitiesOf(context)',
          note: 'What the device can do, which settles and then stays put.',
          read: (context) {
            final can = Bifold.capabilitiesOf(context);
            return can.isResolved
                ? 'resolved, hasFold: ${can.hasFold}'
                : 'not resolved yet';
          },
        ),
        const SizedBox(height: 24),
        Text('Measured arrangement', style: theme.textTheme.titleMedium),
        Text(
          'Where the platform itself would put two panes, measured rather '
          'than modelled.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        const _ArrangementCard(),
      ],
    );
  }
}

/// A card that reads one aspect and reports how often it has been built.
class _Counter extends StatefulWidget {
  const _Counter({
    required this.call,
    required this.note,
    required this.read,
    super.key,
  });

  final String call;
  final String note;
  final String Function(BuildContext context) read;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _builds = 0;

  @override
  Widget build(BuildContext context) {
    // Counted here on purpose: this is the number the page is about.
    _builds++;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.call,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(widget.read(context), style: theme.textTheme.titleSmall),
                  Text(
                    widget.note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: <Widget>[
                Text(
                  '$_builds',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                Text(
                  'builds',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Drives [BifoldArrangement], including the release it asks for.
class _ArrangementCard extends StatefulWidget {
  const _ArrangementCard();

  @override
  State<_ArrangementCard> createState() => _ArrangementCardState();
}

class _ArrangementCardState extends State<_ArrangementCard> {
  ArrangementMeasurement? _measured;
  ArrangementAxis _axis = ArrangementAxis.horizontal;
  bool _measuring = false;
  bool _hasMeasured = false;

  @override
  void dispose() {
    // Measuring attaches a real view controller; it does not release itself.
    BifoldArrangement.release();
    super.dispose();
  }

  Future<void> _measure(Size size) async {
    setState(() => _measuring = true);
    final result = await BifoldArrangement.measure(size: size, axis: _axis);
    if (!mounted) {
      return;
    }
    setState(() {
      _measured = result;
      _measuring = false;
      _hasMeasured = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final measured = _measured;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'BifoldArrangement.measure()',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final box = Size(constraints.maxWidth, 400);
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    SegmentedButton<ArrangementAxis>(
                      segments: const <ButtonSegment<ArrangementAxis>>[
                        ButtonSegment<ArrangementAxis>(
                          value: ArrangementAxis.horizontal,
                          label: Text('horizontal'),
                        ),
                        ButtonSegment<ArrangementAxis>(
                          value: ArrangementAxis.vertical,
                          label: Text('vertical'),
                        ),
                      ],
                      selected: <ArrangementAxis>{_axis},
                      onSelectionChanged: (selection) =>
                          setState(() => _axis = selection.first),
                    ),
                    FilledButton.tonal(
                      onPressed: _measuring ? null : () => _measure(box),
                      child: Text(
                        _measuring
                            ? 'Measuring...'
                            : 'Measure ${box.width.toStringAsFixed(0)}'
                                  '×${box.height.toStringAsFixed(0)}',
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            if (!_hasMeasured)
              Text(
                'Nothing measured yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else if (measured == null)
              Text(
                'The platform reported no arrangement. Expected on every '
                'device without the API, and on a shut one.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else ...<Widget>[
              Text('axis: ${measured.axis.name}'),
              Text('isSplit: ${measured.isSplit}'),
              Text(
                'primary: ${measured.primary.bounds} '
                '(visible: ${measured.primary.isVisible})',
              ),
              Text(
                'secondary: ${measured.secondary.bounds} '
                '(visible: ${measured.secondary.isVisible})',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
