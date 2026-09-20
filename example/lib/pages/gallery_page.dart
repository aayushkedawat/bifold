import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';

/// A photo grid whose rows break at the crease.
///
/// Demonstrates [BifoldGrid] against a plain [GridView], so the difference is
/// visible side by side rather than described.
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  bool _foldAware = true;

  static const List<Color> _palette = <Color>[
    Color(0xFF3D5AFE),
    Color(0xFF00BFA5),
    Color(0xFFFF6E40),
    Color(0xFFAB47BC),
    Color(0xFFFFCA28),
    Color(0xFF26C6DA),
  ];

  @override
  Widget build(BuildContext context) {
    final tiles = List<Widget>.generate(
      24,
      (i) => _Tile(index: i, palette: _palette),
    );

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _foldAware
                      ? 'BifoldGrid — rows stop at the crease'
                      : 'GridView — tiles bend through the crease',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Switch(
                value: _foldAware,
                onChanged: (v) => setState(() => _foldAware = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: _foldAware
              ? BifoldGrid(
                  tileExtent: 110,
                  spacing: 8,
                  padding: const EdgeInsets.all(12),
                  children: tiles,
                )
              : GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  padding: const EdgeInsets.all(12),
                  children: tiles,
                ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.index, required this.palette});

  final int index;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette[index % palette.length].withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          '${index + 1}',
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
