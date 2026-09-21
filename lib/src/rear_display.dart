import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'capabilities.dart';

/// Whether a rear-display mode can be used, and whether it is running.
///
/// Four states rather than a boolean, because "this device cannot do it" and
/// "it could, but not right now" call for different UI: the first means hide
/// the control, the second means disable it.
enum RearDisplayStatus {
  /// The device cannot do this at all.
  unsupported,

  /// Supported, but not possible right now.
  ///
  /// The usual reason is that the system is waiting for something — on the
  /// foldable iPhone, an active camera capture session.
  unavailable,

  /// Ready to start.
  available,

  /// Running now.
  active;

  /// Decodes a status from its platform channel spelling.
  static RearDisplayStatus fromName(String? name) => switch (name) {
        'unavailable' => RearDisplayStatus.unavailable,
        'available' => RearDisplayStatus.available,
        'active' => RearDisplayStatus.active,
        _ => RearDisplayStatus.unsupported,
      };
}

/// The status of every rear-display mode at one moment.
@immutable
class RearDisplayAvailability {
  /// Creates an availability report.
  const RearDisplayAvailability({
    required this.presentation,
    required this.transfer,
  });

  /// Nothing is possible. What every platform without support reports.
  static const RearDisplayAvailability none = RearDisplayAvailability(
    presentation: RearDisplayStatus.unsupported,
    transfer: RearDisplayStatus.unsupported,
  );

  /// Decodes availability from a platform channel map.
  factory RearDisplayAvailability.fromMap(Map<Object?, Object?> map) =>
      RearDisplayAvailability(
        presentation: RearDisplayStatus.fromName(
          map['presentation'] as String?,
        ),
        transfer: RearDisplayStatus.fromName(map['transfer'] as String?),
      );

  /// Content on the second display while the app stays on the first.
  final RearDisplayStatus presentation;

  /// The whole app moving to the second display. Android only.
  final RearDisplayStatus transfer;

  /// The status of one [mode].
  RearDisplayStatus statusOf(RearDisplayMode mode) => switch (mode) {
        RearDisplayMode.presentation => presentation,
        RearDisplayMode.transfer => transfer,
      };

  /// Whether either mode is running right now.
  bool get isActive =>
      presentation == RearDisplayStatus.active ||
      transfer == RearDisplayStatus.active;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RearDisplayAvailability &&
          other.presentation == presentation &&
          other.transfer == transfer;

  @override
  int get hashCode => Object.hash(presentation, transfer);

  @override
  String toString() =>
      'RearDisplayAvailability(presentation: ${presentation.name}, '
      'transfer: ${transfer.name})';
}

/// Shows app content on the display facing the rear camera.
///
/// One API over two quite different platform behaviours:
///
/// * **[present]** puts a second Flutter view on the other display while the
///   app stays where it is. Supported on both platforms — it is what the
///   foldable iPhone's camera capture accessory does, and what Android calls
///   presenting on a window area.
/// * **[transferActivity]** moves the whole app across. Android only; on iOS
///   it reports [RearDisplayStatus.unsupported] and does nothing.
///
/// ## The system is in charge
///
/// Asking is not the same as being shown. The system decides whether and when
/// a session runs and can end one at any time, so treat this as an
/// enhancement: the app must stay usable when it never appears, which is also
/// what happens on every device that has no second display.
///
/// ```dart
/// @pragma('vm:entry-point')
/// void rearDisplayMain() => runApp(const SubjectView());
///
/// // ...once the camera UI is on screen:
/// await BifoldRearDisplay.present(entrypoint: 'rearDisplayMain');
/// ```
///
/// Every method here resolves to a no-op or `false` on unsupported platforms
/// rather than throwing.
abstract final class BifoldRearDisplay {
  static const MethodChannel _methods = MethodChannel('dev.bifold/methods');
  static const EventChannel _events = EventChannel('dev.bifold/rear_display');

  static Stream<RearDisplayAvailability>? _availability;

  /// The status of both modes, updating as the system changes its mind.
  ///
  /// Emits on listen. On platforms with no support it emits
  /// [RearDisplayAvailability.none] and stays open, so a UI can bind to it
  /// unconditionally.
  static Stream<RearDisplayAvailability> get availability {
    return _availability ??= _events
        .receiveBroadcastStream()
        .map(
          (Object? event) => event is Map<Object?, Object?>
              ? RearDisplayAvailability.fromMap(event)
              : RearDisplayAvailability.none,
        )
        .handleError((Object _) {})
        .asBroadcastStream();
  }

  /// Reads the status of both modes once.
  static Future<RearDisplayAvailability> get current async {
    try {
      final Map<Object?, Object?>? payload =
          await _methods.invokeMapMethod<Object?, Object?>('rearDisplayStatus');
      return payload == null
          ? RearDisplayAvailability.none
          : RearDisplayAvailability.fromMap(payload);
    } on MissingPluginException {
      return RearDisplayAvailability.none;
    } on PlatformException {
      return RearDisplayAvailability.none;
    }
  }

  /// Shows [entrypoint]'s content on the rear display.
  ///
  /// [entrypoint] names a top-level function annotated
  /// `@pragma('vm:entry-point')`, which keeps the compiler from dropping it
  /// from a release build. It runs in its own Flutter engine, because one
  /// engine renders one view tree.
  ///
  /// Returns whether a session was started. False means the system said no,
  /// which is not an error.
  static Future<bool> present({
    required String entrypoint,
    String? libraryUri,
  }) async {
    try {
      return await _methods.invokeMethod<bool>(
            'presentOnRearDisplay',
            <String, Object?>{
              'entrypoint': entrypoint,
              'libraryUri': libraryUri,
            },
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'bifold',
          context: ErrorDescription('presenting on the rear display'),
        ),
      );
      return false;
    }
  }

  /// Moves the whole app to the rear display.
  ///
  /// Android only. Returns false everywhere else, and on Android whenever the
  /// system is unwilling.
  static Future<bool> transferActivity() async {
    try {
      return await _methods.invokeMethod<bool>('transferToRearDisplay') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Ends whichever session is running. Safe to call when none is.
  static Future<void> end() async {
    try {
      await _methods.invokeMethod<void>('endRearDisplay');
    } on MissingPluginException {
      // Nothing to end where nothing can start.
    } on PlatformException {
      // Tearing down is best-effort.
    }
  }
}
