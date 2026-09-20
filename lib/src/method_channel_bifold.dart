import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bifold_platform_interface.dart';
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

  @override
  Future<FoldInfo> getFoldInfo() async {
    try {
      final Map<Object?, Object?>? payload = await methodChannel
          .invokeMapMethod<Object?, Object?>('getFoldInfo');
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
  Stream<FoldInfo> foldInfoStream() {
    // Broadcast so that several BifoldScopes can listen without each opening
    // its own native subscription.
    return _stream ??= eventChannel
        .receiveBroadcastStream()
        .map(_decode)
        .handleError(_reportStreamError)
        .asBroadcastStream();
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
