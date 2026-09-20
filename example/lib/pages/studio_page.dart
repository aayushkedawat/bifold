import 'dart:async';

import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';

/// Drives the camera capture accessory.
///
/// With the device open and a capture session running, the system can present
/// app content on the outer display, facing whoever is being filmed. This page
/// registers that content and reports what the system says about it.
///
/// There is no camera session here — that belongs to a camera plugin — so on a
/// simulator `available` stays false. Registration itself is real.
class StudioPage extends StatefulWidget {
  const StudioPage({super.key});

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  bool _supported = false;
  bool _registered = false;
  bool _enabled = false;
  bool _available = false;
  StreamSubscription<bool>? _availability;

  @override
  void initState() {
    super.initState();
    _probe();
    _availability = BifoldCaptureAccessory.availability.listen((value) {
      if (mounted) setState(() => _available = value);
    });
  }

  Future<void> _probe() async {
    final supported = await BifoldCaptureAccessory.isSupported;
    final available = await BifoldCaptureAccessory.isAvailable;
    if (mounted) {
      setState(() {
        _supported = supported;
        _available = available;
      });
    }
  }

  @override
  void dispose() {
    _availability?.cancel();
    // Leaving a registration behind would keep the accessory alive after the
    // page is gone.
    unawaited(BifoldCaptureAccessory.unregister());
    super.dispose();
  }

  Future<void> _toggleRegistration() async {
    if (_registered) {
      await BifoldCaptureAccessory.unregister();
      if (mounted) {
        setState(() {
          _registered = false;
          _enabled = false;
        });
      }
      return;
    }
    final ok = await BifoldCaptureAccessory.register(
      entrypoint: 'captureAccessoryMain',
    );
    if (mounted) setState(() => _registered = ok);
  }

  Future<void> _toggleEnabled(bool value) async {
    await BifoldCaptureAccessory.setEnabled(value);
    if (mounted) setState(() => _enabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Capture accessory', style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Content shown on the outer display while the rear camera is '
          'capturing, so the person being filmed can see their framing — or '
          'read a teleprompter.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _State(label: 'OS supports it', value: _supported),
        _State(label: 'Registered', value: _registered),
        _State(label: 'App asking to show', value: _enabled),
        _State(label: 'System says available', value: _available),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _supported ? _toggleRegistration : null,
          icon: Icon(_registered ? Icons.link_off : Icons.link),
          label: Text(_registered ? 'Unregister' : 'Register accessory'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ask the system to show it'),
          subtitle: const Text(
            'The system still decides whether and where it appears.',
            style: TextStyle(fontSize: 11),
          ),
          value: _enabled,
          onChanged: _registered ? _toggleEnabled : null,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Why available stays false here',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'The accessory only becomes available with an active camera '
                  'capture session, which this example does not open — that is '
                  'a camera plugin’s job. Registration, enabling and the '
                  'availability stream are all live.',
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

class _State extends StatelessWidget {
  const _State({required this.label, required this.value});

  final String label;
  final bool value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Icon(
            value ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: value ? scheme.primary : scheme.outline,
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
