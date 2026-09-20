import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shows app content on the outer display while the camera is capturing.
///
/// With the device open, a capture session running and the app full screen on
/// the inner display, the system can present content on the outer display —
/// facing the person being filmed. The canonical uses are letting a subject
/// see their own framing, and a teleprompter.
///
/// ## Setting it up
///
/// The accessory renders in its own Flutter engine, so it needs its own
/// entrypoint, annotated so the compiler keeps it in a release build:
///
/// ```dart
/// @pragma('vm:entry-point')
/// void captureAccessoryMain() {
///   runApp(const SubjectView());
/// }
///
/// void main() {
///   runApp(const BifoldScope(child: MyCameraApp()));
/// }
/// ```
///
/// Then register it once the camera UI is on screen:
///
/// ```dart
/// await BifoldCaptureAccessory.register(entrypoint: 'captureAccessoryMain');
/// await BifoldCaptureAccessory.setEnabled(true);
/// ```
///
/// ## The system is in charge
///
/// [setEnabled] says the app *would like* the accessory shown.
/// [availability] reports whether the system says it *can* be. The system
/// decides whether and where it actually appears, and it will not appear at
/// all without an active capture session. Treat it as an enhancement: the app
/// must stay fully functional when it never shows, which is also what happens
/// on every device that is not a foldable.
///
/// Every method here resolves to a no-op or `false` on unsupported platforms
/// rather than throwing.
abstract final class BifoldCaptureAccessory {
  static const MethodChannel _methods = MethodChannel('dev.bifold/methods');
  static const EventChannel _events = EventChannel(
    'dev.bifold/capture_accessory',
  );

  static Stream<bool>? _availability;

  /// Whether this OS can present a camera capture accessory at all.
  ///
  /// False on every platform other than iOS 27.1 and later.
  static Future<bool> get isSupported async {
    try {
      return await _methods.invokeMethod<bool>('captureAccessorySupported') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Registers [entrypoint] as the accessory's content.
  ///
  /// [entrypoint] is the name of a top-level Dart function annotated with
  /// `@pragma('vm:entry-point')`. [libraryUri] names the library it lives in,
  /// and defaults to the app's `main.dart`.
  ///
  /// Returns whether registration succeeded. False means the platform cannot
  /// present an accessory, which is not an error.
  static Future<bool> register({
    required String entrypoint,
    String? libraryUri,
  }) async {
    try {
      final bool? registered = await _methods
          .invokeMethod<bool>('registerCaptureAccessory', <String, Object?>{
        'entrypoint': entrypoint,
        'libraryUri': libraryUri,
      });
      return registered ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'bifold',
          context: ErrorDescription('registering the capture accessory'),
        ),
      );
      return false;
    }
  }

  /// Removes the registration.
  ///
  /// If the accessory is on screen, the system dismisses it.
  static Future<void> unregister() async {
    try {
      await _methods.invokeMethod<void>('unregisterCaptureAccessory');
    } on MissingPluginException {
      // Nothing registered on a platform that cannot register anything.
    } on PlatformException {
      // Tearing down is best-effort.
    }
  }

  /// Asks for the accessory to be shown, or stops asking.
  ///
  /// This does not force it on screen: the system still decides. Pair it with
  /// the lifetime of the capture session.
  static Future<void> setEnabled(bool enabled) async {
    try {
      await _methods.invokeMethod<void>(
        'setCaptureAccessoryEnabled',
        <String, Object?>{'enabled': enabled},
      );
    } on MissingPluginException {
      // No accessory to enable.
    } on PlatformException {
      // Best-effort.
    }
  }

  /// Whether the system currently says the accessory can be presented.
  static Future<bool> get isAvailable async {
    try {
      return await _methods.invokeMethod<bool>(
            'isCaptureAccessoryAvailable',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Emits whenever the system's availability for the accessory changes.
  ///
  /// Emits the current value on listen. On unsupported platforms it emits
  /// `false` and stays open, so a UI can bind to it unconditionally.
  static Stream<bool> get availability {
    return _availability ??= _events
        .receiveBroadcastStream()
        .map((Object? event) => event == true)
        .handleError((Object _) {})
        .asBroadcastStream();
  }
}
