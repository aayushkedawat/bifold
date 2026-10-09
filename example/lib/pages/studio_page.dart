import 'dart:async';

import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';

/// Drives the rear display.
///
/// Content on the display that faces the rear camera, so the person being
/// filmed can see their framing — or read a teleprompter. One API over two
/// quite different platform behaviours: presenting alongside the app, and
/// moving the whole app across.
///
/// This page is the showcase for the three-way distinction the package is
/// built around, so it keeps them visibly separate:
///
/// * **capability** — could this device ever do it? Stable, so a control keyed
///   on it never flickers.
/// * **availability** — may it right now? Moves with the system, so a control
///   keyed on it dims rather than disappearing.
/// * **state** — is it running at this moment?
///
/// There is no camera session here — that belongs to a camera plugin — so on
/// iOS `available` stays false, because the system will not present an
/// accessory without one. Everything else is live.
class StudioPage extends StatefulWidget {
  const StudioPage({super.key});

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  /// Starts unresolved rather than unsupported, which is the distinction the
  /// four-state status exists for: nothing has reported yet.
  RearDisplayAvailability _availability = RearDisplayAvailability.unresolved;
  StreamSubscription<RearDisplayAvailability>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = BifoldRearDisplay.availability.listen((value) {
      if (mounted) setState(() => _availability = value);
    });
    unawaited(_probe());
  }

  Future<void> _probe() async {
    final current = await BifoldRearDisplay.current;
    if (mounted) setState(() => _availability = current);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    // Leaving a session behind would keep content on the other display after
    // the page is gone.
    unawaited(BifoldRearDisplay.end());
    super.dispose();
  }

  Future<void> _present() async {
    // Returns false when the system says no, which is not an error.
    await BifoldRearDisplay.present(entrypoint: 'rearDisplayMain');
    await _probe();
  }

  Future<void> _transfer() async {
    await BifoldRearDisplay.transferActivity();
    await _probe();
  }

  Future<void> _end() async {
    await BifoldRearDisplay.end();
    await _probe();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final can = Bifold.capabilitiesOf(context);
    final presentation = _availability.presentation;
    final transfer = _availability.transfer;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Rear display', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Content on the display facing the rear camera. On iOS this is the '
          'camera capture accessory; on Android it is presenting on a window '
          'area. Moving the whole app across is Android only.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),

        // Capability first, and separately: it answers a different question
        // from the statuses below it.
        Text('Capability', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          can.hasRearDisplay
              ? 'This device can put content on another display.'
              : switch (can.statusOf(FoldFeature.rearDisplay)) {
                  CapabilityStatus.unknown =>
                    'Not established yet — which is '
                        'not the same as no.',
                  _ => 'This device cannot.',
                },
          style: theme.textTheme.bodySmall,
        ),
        if (can.rearDisplayModes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            'Modes: ${can.rearDisplayModes.map((m) => m.name).join(', ')}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const Divider(height: 24),

        Text('Availability', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        if (!_availability.isResolved)
          Text(
            'Waiting for the platform to report.',
            style: theme.textTheme.bodySmall,
          ),
        _StatusRow(label: 'Presentation', status: presentation),
        _StatusRow(label: 'Transfer', status: transfer),
        const SizedBox(height: 16),

        // Enabled on availability, shown on capability. Collapsing the two
        // would make the button either lie or flicker.
        FilledButton.icon(
          onPressed: presentation == RearDisplayStatus.available
              ? _present
              : null,
          icon: const Icon(Icons.cast),
          label: const Text('Present on the rear display'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: transfer == RearDisplayStatus.available ? _transfer : null,
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Move the whole app across'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _availability.isActive ? _end : null,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('End the session'),
        ),
        const SizedBox(height: 16),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Why a mode can be supported but unavailable',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'The system decides whether a session runs, and can end one '
                  'at any time. On iOS it will not present an accessory '
                  'without an active camera capture session, which this '
                  'example does not open — that is a camera plugin’s job. '
                  'Treat the whole feature as an enhancement: the app has to '
                  'stay usable when it never appears, which is also what '
                  'happens on every device with only one display.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.status});

  final String label;
  final RearDisplayStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color colour) = switch (status) {
      RearDisplayStatus.unsupported => (Icons.block, scheme.outline),
      RearDisplayStatus.unavailable => (
        Icons.pause_circle_outline,
        scheme.tertiary,
      ),
      RearDisplayStatus.available => (
        Icons.check_circle_outline,
        scheme.primary,
      ),
      RearDisplayStatus.active => (Icons.play_circle, scheme.primary),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: 8),
          Text('$label: ${status.name}', style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
