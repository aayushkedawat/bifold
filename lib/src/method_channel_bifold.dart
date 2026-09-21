import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bifold_platform_interface.dart';
import 'capabilities.dart';
import 'models.dart';

/// The name of the method channel used for one-shot queries.
@visibleForTesting
const String kBifoldMethodChannelName = 'dev.bifold/methods';

/// The name of the event channel that carries fold state updates.
@visibleForTesting
const String kBifoldEventChannelName = 'dev.bifold/fold_info';

/// The [BifoldPlatform] implementation backed by platform channels.
///
/// Every failure path here resolves to [FoldInfo.unsupported] rather than an
/// exception. A missing plugin (any non-iOS platform), an OS without the fold
/// APIs, and a malformed payload are all "this device has no fold", which is a
/// state callers already have to handle.
class MethodChannelBifold extends BifoldPlatform {
  /// The channel used for one-shot queries.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(
    kBifoldMethodChannelName,
  );

  /// The channel used for the fold state stream.
  @visibleForTesting
  final EventChannel eventChannel = const EventChannel(
    kBifoldEventChannelName,
  );

  Stream<FoldInfo>? _stream;
  Stream<BifoldCapabilities>? _capabilities;

  /// Applies the stickiness and evidence rules across every report.
  final CapabilityResolver _resolver = CapabilityResolver();

  @override
  Future<FoldInfo> getFoldInfo() async {
    try {
      final Map<Object?, Object?>? payload =
          await methodChannel.invokeMapMethod<Object?, Object?>('getFoldInfo');
      if (payload == null) {
        return FoldInfo.unsupported;
      }
      return FoldInfo.fromMap(payload);
    } on MissingPluginException {
      // No native side: every platform other than iOS.
      return FoldInfo.unsupported;
    } on PlatformException catch (error, stack) {
      // The native side reports failures with stable codes. None of them are
      // recoverable from Dart, and none of them should take down the app.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'bifold',
          context: ErrorDescription('reading fold info'),
        ),
      );
      return FoldInfo.unsupported;
    }
  }

  @override
  Future<BifoldCapabilities> getCapabilities() async {
    try {
      final Map<Object?, Object?>? payload = await methodChannel
          .invokeMapMethod<Object?, Object?>('getCapabilities');
      if (payload == null) {
        return _resolver.absorb(BifoldCapabilities.none);
      }
      return _resolver.absorb(BifoldCapabilities.fromMap(payload));
    } on MissingPluginException {
      // No native side. That is an answer, not a failure: this platform has
      // no fold support of any kind.
      return _resolver.absorb(BifoldCapabilities.none);
    } on PlatformException catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'bifold',
          context: ErrorDescription('reading fold capabilities'),
        ),
      );
      // The plugin is there and unhappy. Claiming "no fold support" would be
      // a stronger statement than the evidence allows.
      return _resolver.current;
    }
  }

  @override
  Stream<BifoldCapabilities> capabilitiesStream() {
    // Capabilities are derived from the same native reports the fold stream
    // carries, so this rides along rather than opening a second subscription.
    return _capabilities ??= foldInfoStream()
        .asyncMap((FoldInfo _) => getCapabilities())
        .distinct()
        .asBroadcastStream();
  }

  @override
  Future<String?> debugDescribeNativeApi() async {
    try {
      return await methodChannel.invokeMethod<String>(
        'debugDescribeNativeApi',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Stream<FoldInfo> foldInfoStream() {
    // Broadcast so that several BifoldScopes can listen without each opening
    // its own native subscription.
    return _stream ??= _guardedStream();
  }

  /// Subscribes to the event channel only once the method channel has
  /// confirmed there is a native side to subscribe to.
  ///
  /// Listening to an event channel with no handler is not a failure this class
  /// can absorb. [EventChannel.receiveBroadcastStream] catches its own failed
  /// `listen` call and reports it through [FlutterError.reportError] rather
  /// than adding it to the stream, so it reaches the console whatever this
  /// stream does with its errors. Asking the method channel first keeps a
  /// platform with no native side quiet, which is the normal case on Android,
  /// web and desktop.
  Stream<FoldInfo> _guardedStream() {
    StreamSubscription<FoldInfo>? native;
    late final StreamController<FoldInfo> controller;

    Future<void> start() async {
      final bool present = await _nativeSideIsPresent();
      if (!controller.hasListener) {
        // Everyone stopped listening while the probe was in flight.
        return;
      }
      if (!present) {
        controller.add(FoldInfo.unsupported);
        return;
      }
      native = eventChannel
          .receiveBroadcastStream()
          .map(_decode)
          .listen(controller.add, onError: _reportStreamError);
    }

    controller = StreamController<FoldInfo>.broadcast(
      // Synchronous so that forwarding through this controller costs no extra
      // microtask, and an event reaches listeners in the same turn it would
      // have before this stream was placed in front of the event channel.
      // Every add() below happens inside a stream callback or after an await,
      // never re-entrantly during listen(), which is what makes that safe.
      sync: true,
      onListen: () => unawaited(start()),
      onCancel: () {
        native?.cancel();
        native = null;
      },
    );
    return controller.stream;
  }

  /// Whether a native implementation is registered on the method channel.
  ///
  /// A [PlatformException] counts as present: the native side answered, badly,
  /// which is a different thing from not being there at all.
  Future<bool> _nativeSideIsPresent() async {
    try {
      await methodChannel.invokeMethod<Object?>('getFoldInfo');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return true;
    }
  }

  static FoldInfo _decode(Object? event) {
    if (event is Map<Object?, Object?>) {
      return FoldInfo.fromMap(event);
    }
    return FoldInfo.unsupported;
  }

  static void _reportStreamError(Object error, StackTrace stack) {
    if (error is MissingPluginException) {
      // Expected on every platform without a native implementation.
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'bifold',
        context: ErrorDescription('listening for fold info updates'),
      ),
    );
  }
}
