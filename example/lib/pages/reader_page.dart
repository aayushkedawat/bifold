import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';

/// Two pages of a book, laid out either side of the fold.
///
/// Demonstrates [BifoldSplit] and [bifoldAnchorPoint].
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  BifoldSplitFallback _fallback = BifoldSplitFallback.stack;
  int _spread = 0;

  static const List<List<String>> _spreads = <List<String>>[
    <String>[
      'The panes above and below this line are placed clear of the crease and '
          'its margins. Fold the device part-way to watch them separate.',
      'When there is no active division — flat, shut, or a phone that does not '
          'fold — the two pages stack instead. Nothing throws, nothing hides.',
    ],
    <String>[
      'A reserved region is not part of the safe area. The safe area keeps '
          'content clear of system UI; a reserved region keeps it clear of the '
          'hardware itself.',
      'The frame the platform reports already includes its margins. Content '
          'that must stay legible clears the whole frame; decoration may run '
          'into the margins.',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final pages = _spreads[_spread];

    return Column(
      children: <Widget>[
        _Toolbar(
          fallback: _fallback,
          onFallback: (value) => setState(() => _fallback = value),
          onTurn: () =>
              setState(() => _spread = (_spread + 1) % _spreads.length),
          onDialog: () => _showDialog(context),
        ),
        Expanded(
          child: BifoldSplit(
            fallback: _fallback,
            start: _Page(
              number: _spread * 2 + 1,
              title: 'On folding',
              body: pages[0],
            ),
            end: _Page(
              number: _spread * 2 + 2,
              title: 'On falling back',
              body: pages[1],
            ),
          ),
        ),
      ],
    );
  }

  void _showDialog(BuildContext context) {
    // The anchor point keeps this off the crease. It returns null when there
    // is nothing to avoid, so it is safe to pass unconditionally.
    showDialog<void>(
      context: context,
      anchorPoint: bifoldAnchorPoint(context),
      builder: (context) => AlertDialog(
        title: const Text('Anchored clear of the fold'),
        content: const Text(
          'Without an anchor point this dialog would centre itself, straddling '
          'the crease with its title on one half and its buttons on the other.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.fallback,
    required this.onFallback,
    required this.onTurn,
    required this.onDialog,
  });

  final BifoldSplitFallback fallback;
  final ValueChanged<BifoldSplitFallback> onFallback;
  final VoidCallback onTurn;
  final VoidCallback onDialog;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          const Text('fallback: ', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          SegmentedButton<BifoldSplitFallback>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll<TextStyle>(
                TextStyle(fontSize: 11),
              ),
            ),
            segments: const <ButtonSegment<BifoldSplitFallback>>[
              ButtonSegment(
                value: BifoldSplitFallback.stack,
                label: Text('stack'),
              ),
              ButtonSegment(
                value: BifoldSplitFallback.sideBySide,
                label: Text('side'),
              ),
              ButtonSegment(
                value: BifoldSplitFallback.startOnly,
                label: Text('one'),
              ),
            ],
            selected: <BifoldSplitFallback>{fallback},
            onSelectionChanged: (values) => onFallback(values.first),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onTurn,
            icon: const Icon(Icons.chevron_right, size: 16),
            label: const Text('Turn', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onDialog,
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            label: const Text('Dialog', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.number, required this.title, required this.body});

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
