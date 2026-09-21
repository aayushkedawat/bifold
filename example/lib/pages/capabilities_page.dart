import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What this device *can* do, with the platform signal behind each answer.
///
/// The companion to the inspector, which shows what the device *is* doing.
/// Together they are the pair to screenshot in a bug report.
class CapabilitiesPage extends StatelessWidget {
  /// Creates the capabilities page.
  const CapabilitiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final can = Bifold.capabilitiesOf(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'BifoldCapabilities',
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Copy the diagnostic report',
              onPressed: () async {
                final report = await Bifold.diagnosticReport();
                await Clipboard.setData(ClipboardData(text: report));
              },
              icon: const Icon(Icons.copy, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // The distinction the whole type exists for, stated where it is
        // impossible to miss.
        if (!can.isResolved)
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Not resolved yet. Every answer below is "unknown" because '
                'nothing has reported, not because the answer is no.',
              ),
            ),
          ),

        const SizedBox(height: 8),
        _Chips(<String>[
          'resolved: ${can.isResolved}',
          'form factor: ${can.formFactor.name}',
          if (can.rearDisplayModes.isEmpty)
            'no rear display modes'
          else
            'modes: ${can.rearDisplayModes.map((m) => m.name).join(', ')}',
        ]),
        const SizedBox(height: 16),

        for (final feature in FoldFeature.values)
          _CapabilityRow(feature: feature, evidence: can.evidenceOf(feature)),

        const SizedBox(height: 24),
        Text('Why this is not a boolean', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          'A capability that reads false may be a proven no, or may simply be '
          'unestablished. Observation can only ever move an answer up to '
          'supported: never having seen a fold is not evidence that the '
          'device cannot fold, which is why a closed foldable still reports '
          'hasFold true from a static device signal.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.feature, required this.evidence});

  final FoldFeature feature;
  final CapabilityEvidence evidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (
      IconData icon,
      Color colour,
      String label,
    ) = switch (evidence.status) {
      CapabilityStatus.supported => (
        Icons.check_circle_outline,
        theme.colorScheme.primary,
        'supported',
      ),
      CapabilityStatus.unsupported => (
        Icons.cancel_outlined,
        theme.colorScheme.error,
        'unsupported',
      ),
      CapabilityStatus.unknown => (
        Icons.help_outline,
        theme.disabledColor,
        'unknown',
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(feature.name, style: theme.textTheme.bodyMedium),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(color: colour),
                ),
                // The source is the point: it says why, not just what.
                if (evidence.source case final source?)
                  Text(
                    source,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.disabledColor,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips(this.labels);

  final List<String> labels;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      for (final label in labels)
        Chip(label: Text(label), visualDensity: VisualDensity.compact),
    ],
  );
}
