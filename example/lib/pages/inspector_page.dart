import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Every field of [FoldInfo], plus each reserved region in full.
///
/// This is the page to screenshot in a bug report: it shows exactly what the
/// platform handed the package, with no interpretation.
class InspectorPage extends StatelessWidget {
  const InspectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final info = Bifold.of(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('FoldInfo', style: theme.textTheme.titleMedium),
            ),
            IconButton(
              tooltip: 'Copy as text',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _describe(info))),
              icon: const Icon(Icons.copy, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Row('isFoldable', '${info.isFoldable}'),
        _Row('display', info.display.name),
        _Row('pose', info.pose.name),
        _Row(
          'hingeAngle',
          info.hingeAngle == null
              ? 'null'
              : '${info.hingeAngle!.toStringAsFixed(4)} rad '
                    '(${info.hingeAngleDegrees!.toStringAsFixed(1)}°)',
        ),
        _Row('horizontalSizeClass', info.horizontalSizeClass.name),
        _Row('verticalSizeClass', info.verticalSizeClass.name),
        _Row('isRegular', '${info.isRegular}'),
        _Row('verticalBarEdge', info.verticalBarEdge.name),
        _Row('division', info.division == null ? 'null' : 'active'),
        const SizedBox(height: 16),
        Text(
          'Regions (${info.regions.length})',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (info.regions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No reserved regions. Expected while the device is shut or on '
                'the outer display; on the inner display, open the device to '
                'see the fold appear.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          )
        else
          for (final region in info.regions) _RegionCard(region: region),
      ],
    );
  }

  static String _describe(FoldInfo info) {
    final buffer = StringBuffer()
      ..writeln('isFoldable: ${info.isFoldable}')
      ..writeln('display: ${info.display.name}')
      ..writeln('pose: ${info.pose.name}')
      ..writeln('hingeAngle: ${info.hingeAngle}')
      ..writeln(
        'sizeClass: ${info.horizontalSizeClass.name}/'
        '${info.verticalSizeClass.name}',
      )
      ..writeln('verticalBarEdge: ${info.verticalBarEdge.name}')
      ..writeln('regions: ${info.regions.length}');
    for (final region in info.regions) {
      buffer.writeln('  $region');
    }
    return buffer.toString();
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegionCard extends StatelessWidget {
  const _RegionCard({required this.region});

  final FoldRegion region;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colour = region.kind == RegionKind.division
        ? const Color(0xFF00E5FF)
        : const Color(0xFFFF4081);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(width: 10, height: 10, color: colour),
                const SizedBox(width: 8),
                Text(
                  region.kind.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  region.isActive ? 'active' : 'inactive',
                  style: TextStyle(
                    fontSize: 11,
                    color: region.isActive ? scheme.primary : scheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Row('frame (avoid)', _rect(region.frame)),
            _Row('reservedRect', _rect(region.reservedRect)),
            _Row('margins', '${region.margins}'),
          ],
        ),
      ),
    );
  }

  static String _rect(Rect r) =>
      'L${r.left.toStringAsFixed(1)} T${r.top.toStringAsFixed(1)} '
      'R${r.right.toStringAsFixed(1)} B${r.bottom.toStringAsFixed(1)}';
}
