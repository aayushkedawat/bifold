import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One pane of a measured arrangement.
@immutable
class ArrangementPane {
  /// Creates a measured pane.
  const ArrangementPane({required this.bounds, required this.isVisible});

  /// Where the platform placed this pane, relative to the measured box.
  final Rect bounds;

  /// Whether the platform would show this pane at all.
  ///
  /// False when the arrangement collapses to a single pane — which is what
  /// happens on the outer display, and when the device is shut.
  final bool isVisible;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrangementPane &&
          other.bounds == bounds &&
          other.isVisible == isVisible;

  @override
  int get hashCode => Object.hash(bounds, isVisible);

  @override
  String toString() => 'ArrangementPane($bounds, visible: $isVisible)';
}

/// Which way a split arrangement divides its box.
enum ArrangementAxis {
  /// Panes sit side by side.
  horizontal,

  /// Panes sit one above the other.
  vertical;

  /// The spelling used on the platform channel.
  String get wireName => name;
}

/// Where the platform's own split arrangement would place two panes.
@immutable
class ArrangementMeasurement {
  /// Creates a measurement.
  const ArrangementMeasurement({
    required this.primary,
    required this.secondary,
    required this.axis,
  });

  /// Decodes a measurement from a platform channel map.
  factory ArrangementMeasurement.fromMap(Map<Object?, Object?> map) {
    ArrangementPane pane(Object? raw) {
      if (raw is! Map<Object?, Object?>) {
        return const ArrangementPane(bounds: Rect.zero, isVisible: false);
      }
      double number(String key) {
        final value = raw[key];
        return value is num ? value.toDouble() : 0.0;
      }

      return ArrangementPane(
        bounds: Rect.fromLTRB(
          number('left'),
          number('top'),
          number('right'),
          number('bottom'),
        ),
        isVisible: raw['visible'] == true,
      );
    }

    return ArrangementMeasurement(
      primary: pane(map['primary']),
      secondary: pane(map['secondary']),
      axis: map['axis'] == 'vertical'
          ? ArrangementAxis.vertical
          : ArrangementAxis.horizontal,
    );
  }

  /// The leading pane.
  final ArrangementPane primary;

  /// The trailing pane.
  final ArrangementPane secondary;

  /// Which way the split runs.
  final ArrangementAxis axis;

  /// Whether the platform is showing two panes rather than collapsing to one.
  bool get isSplit => primary.isVisible && secondary.isVisible;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrangementMeasurement &&
          other.primary == primary &&
          other.secondary == secondary &&
          other.axis == axis;

  @override
  int get hashCode => Object.hash(primary, secondary, axis);

  @override
  String toString() =>
      'ArrangementMeasurement(${axis.name}, $primary, $secondary)';
}

/// Asks the platform where *it* would place two panes.
///
/// [BifoldSplit] positions panes itself, from the reported fold. This asks a
/// different question: what would the platform's own split arrangement do with
/// a box of this size? Use it when a layout needs to match system behaviour
/// exactly rather than approximate it — the measurement comes from a real
/// arrangement that the platform laid out, not from a model of one.
///
/// ```dart
/// final measured = await BifoldArrangement.measure(
///   size: const Size(871, 669),
///   axis: ArrangementAxis.vertical,
/// );
/// if (measured != null && measured.isSplit) {
///   // Mirror measured.primary.bounds and measured.secondary.bounds.
/// }
/// ```
///
/// ## What it costs
///
/// Measuring attaches a real, empty view controller to the app's hierarchy —
/// the platform will not lay out something hidden, and an unlaid-out
/// measurement is worthless. It renders nothing, takes no input and is hidden
/// from accessibility, but it is not free. Call [release] when finished.
///
/// Returns null on every platform that has no arrangement API.
abstract final class BifoldArrangement {
  static const MethodChannel _channel = MethodChannel('dev.bifold/methods');

  /// Measures a split of [size] along [axis].
  ///
  /// Returns null when the platform reports no arrangement, which includes
  /// every device without the API.
  static Future<ArrangementMeasurement?> measure({
    required Size size,
    ArrangementAxis axis = ArrangementAxis.horizontal,
  }) async {
    try {
      final Map<Object?, Object?>? result = await _channel
          .invokeMapMethod<Object?, Object?>('measureArrangement', <String, Object?>{
            'width': size.width,
            'height': size.height,
            'axis': axis.wireName,
          });
      if (result == null) {
        return null;
      }
      return ArrangementMeasurement.fromMap(result);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Releases the view controller [measure] attached.
  ///
  /// Safe to call when nothing was attached.
  static Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('releaseArrangement');
    } on MissingPluginException {
      // Nothing to release.
    } on PlatformException {
      // Best effort.
    }
  }
}
