import 'package:flutter/material.dart';

import '../downstream/hinge_creature.dart';
import '../downstream/rear_display_camera.dart';
import '../downstream/two_pane.dart';

/// The three downstream consumers, running for real.
///
/// Each was written against the public API with **no platform checks at all**,
/// which is the test they exist for: if any of them needed to know whether it
/// was on iOS or Android, the abstraction would have failed.
class DownstreamPage extends StatefulWidget {
  /// Creates the downstream examples page.
  const DownstreamPage({super.key});

  @override
  State<DownstreamPage> createState() => _DownstreamPageState();
}

class _DownstreamPageState extends State<DownstreamPage> {
  int _which = 0;

  static const List<String> _labels = <String>[
    'creature',
    'two pane',
    'camera',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<int>(
            segments: <ButtonSegment<int>>[
              for (var i = 0; i < _labels.length; i++)
                ButtonSegment<int>(value: i, label: Text(_labels[i])),
            ],
            selected: <int>{_which},
            onSelectionChanged: (s) => setState(() => _which = s.first),
            showSelectedIcon: false,
          ),
        ),
        Expanded(
          child: switch (_which) {
            0 => const HingeCreature(),
            1 => const TwoPane(
              start: Center(child: Text('list')),
              end: Center(child: Text('detail')),
            ),
            _ => const RearDisplayCamera(),
          },
        ),
      ],
    );
  }
}
