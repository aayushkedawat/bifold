import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bifold_platform_interface.dart';
import 'capabilities.dart';
import 'models.dart';
import 'rear_display.dart';

/// The name of the method channel used for one-shot queries.
@visibleForTesting
const String kBifoldMethodChannelName = 'dev.bifold/methods';

/// The name of the event channel that carries fold state updates.
@visibleForTesting
const String kBifoldEventChannelName = 'dev.bifold/fold_info';

/// The name of the event channel that carries rear-display availability.
@visibleForTesting
const String kBifoldRearDisplayChannelName = 'dev.bifold/rear_display';

/// Whether a native implementation is registered on [channel].
///
/// Calls [method] purely to see whether anything answers, so it must name a
/// method with no side effects. A [PlatformException] counts as present: the
/// native side answered, badly, which is a different thing from not being
/// there at all.
///
/// Internal plumbing, shared by every guarded stream below.
Future<bool> nativeSideIsPresent(MethodChannel channel, String method) async {
  try {
    await channel.invokeMethod<Object?>(method);
    return true;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return true;
  }
}

/// Wraps [channel] so a platform with no native side settles on [absent].
///
/// Listening to an event channel with no handler is not a failure the caller
/// can absorb. [EventChannel.receiveBroadcastStream] catches its own failed
/// `listen` and reports it through [FlutterError.reportError] rather than
/// adding it to the stream, so it reaches the console whatever the caller does
/// with the stream's errors. Probing the method channel first keeps a platform
/// with no native side quiet, which is the normal case on web and desktop.
///
/// Emitting [absent] rather than nothing is the other half of it: every one of
/// these streams is documented as safe to bind a UI to unconditionally, and a
/// stream that emits nothing at all leaves a `StreamBuilder` on its null
/// snapshot forever, which is the one state such a UI has no reason to handle.
///
/// [probe] reports whether there is a native side, [decode] turns a channel
/// event into a value, and [errorContext] describes the subscription in any
/// error this reports. Internal plumbing: callers reach these streams through
/// [BifoldPlatform].
Stream<T> guardedEventChannelStream<T>({
  required EventChannel channel,
  required Future<bool> Function() probe,
  required T Function(Object? event) decode,
  required T absent,
  required String errorContext,
}) {
  StreamSubscription<T>? native;
  late final StreamController<T> controller;

  Future<void> start() async {
    final bool present = await probe();
    if (!controller.hasListener) {
      // Everyone stopped listening while the probe was in flight.
      return;
    }
    if (!present) {
      // Settled: there is no native side to report anything.
      controller.add(absent);
      return;
    }
    native = channel.receiveBroadcastStream().map(decode).listen(
          controller.add,
          onError: (Object error, StackTrace stack) =>
              _reportStreamError(error, stack, errorContext),
        );
  }

  controller = StreamController<T>.broadcast(
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

void _reportStreamError(Object error, StackTrace stack, String context) {
  if (error is MissingPluginException) {
    // Expected on every platform without a native implementation.
    return;
  }
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'bifold',
      context: ErrorDescription(context),
    ),
  );
}

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

  /// The channel used for the rear-display availability stream.
  @visibleForTesting
  final EventChannel rearDisplayChannel = const EventChannel(
    kBifoldRearDisplayChannelName,
  );

  Stream<FoldInfo>? _stream;
  Stream<BifoldCapabilities>? _capabilities;
  Stream<RearDisplayAvailability>? _rearDisplay;

  /// Applies the stickiness and evidence rules across every report.
  final CapabilityResolver _resolver = CapabilityResolver();

  @override
  Future<FoldInfo> getFoldInfo() async {
    try {
      final Map<Object?, Object?>? payload =
          await methodChannel.invokeMapMethod<Object?, Object?>('getFoldInfo');
      if (payload == null) {
        return FoldInfo.none;
      }
      return FoldInfo.fromMap(payload);
    } on MissingPluginException {
      // No native side: web, desktop, and anywhere the plugin is not
      // registered. Having no implementation is itself a conclusive answer,
      // so this is `none` rather than `unsupported` -- the latter means
      // "nothing has reported yet" and would never resolve.
      return FoldInfo.none;
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

  /// The `capabilityRevision` of the last fold payload that prompted a query.
  ///
  /// Starts below zero so the first event always queries.
  int _queriedRevision = -1;

  @override
  Stream<BifoldCapabilities> capabilitiesStream() {
    // Capabilities ride on the fold stream rather than opening a second
    // native subscription -- but they must not be re-fetched per event. The
    // fold stream carries a hinge angle, so it fires at sensor rate; querying
    // on every event cost one platform round trip per sample (measured: 60
    // events, 60 round trips, one useful emission) to re-derive a value whose
    // own stickiness rules make it nearly immutable.
    //
    // The native side stamps each fold payload with a `capabilityRevision`
    // that it bumps only when the capability map it would report actually
    // changes. Gating on that leaves the common case -- a fold in progress --
    // at zero round trips, while a real capability change still arrives,
    // because the native side emits a fold event when it bumps the revision.
    return _capabilities ??= foldInfoStream()
        .where(_revisionChanged)
        .asyncMap((FoldInfo _) => getCapabilities())
        .distinct()
        .asBroadcastStream();
  }

  /// Whether [info] carries a capability revision not yet queried for.
  ///
  /// A payload with no revision key counts as revision zero, so a native build
  /// that predates the key still resolves once instead of never.
  bool _revisionChanged(FoldInfo info) {
    final int revision = info.capabilityRevision;
    if (revision == _queriedRevision) {
      return false;
    }
    _queriedRevision = revision;
    return true;
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
    return _stream ??= guardedEventChannelStream<FoldInfo>(
      channel: eventChannel,
      probe: () => nativeSideIsPresent(methodChannel, 'getFoldInfo'),
      decode: _decodeFold,
      absent: FoldInfo.none,
      errorContext: 'listening for fold info updates',
    );
  }

  @override
  Future<RearDisplayAvailability> rearDisplayStatus() async {
    try {
      final Map<Object?, Object?>? payload = await methodChannel
          .invokeMapMethod<Object?, Object?>('rearDisplayStatus');
      return payload == null
          ? RearDisplayAvailability.none
          : RearDisplayAvailability.fromMap(payload);
    } on MissingPluginException {
      // No native side is a settled answer: nothing here can present.
      return RearDisplayAvailability.none;
    } on PlatformException {
      // The plugin is there and unhappy, which says nothing about the device.
      return RearDisplayAvailability.unresolved;
    }
  }

  @override
  Stream<RearDisplayAvailability> rearDisplayAvailabilityStream() {
    return _rearDisplay ??= guardedEventChannelStream<RearDisplayAvailability>(
      channel: rearDisplayChannel,
      probe: () => nativeSideIsPresent(methodChannel, 'rearDisplayStatus'),
      decode: _decodeRearDisplay,
      absent: RearDisplayAvailability.none,
      errorContext: 'listening for rear display availability',
    );
  }

  @override
  Future<bool> presentOnRearDisplay({
    required String entrypoint,
    String? libraryUri,
  }) async {
    try {
      return await methodChannel.invokeMethod<bool>(
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
      // Unlike the other three, this one is worth a console entry: the app
      // asked for something and the plugin refused for a reason the
      // developer can act on, such as a missing entrypoint annotation.
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

  @override
  Future<bool> transferToRearDisplay() async {
    try {
      return await methodChannel.invokeMethod<bool>(
            'transferToRearDisplay',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> endRearDisplay() async {
    try {
      await methodChannel.invokeMethod<void>('endRearDisplay');
    } on MissingPluginException {
      // Nothing to end where nothing can start.
    } on PlatformException {
      // Tearing down is best-effort.
    }
  }

  static FoldInfo _decodeFold(Object? event) {
    if (event is Map<Object?, Object?>) {
      return FoldInfo.fromMap(event);
    }
    // An event that is not a map is a native bug rather than a device without
    // a fold, so this claims nothing: `unsupported` leaves isResolved false.
    return FoldInfo.unsupported;
  }

  static RearDisplayAvailability _decodeRearDisplay(Object? event) {
    if (event is Map<Object?, Object?>) {
      return RearDisplayAvailability.fromMap(event);
    }
    // Same reasoning as the fold stream: claim nothing rather than report a
    // settled "this device cannot present" on the strength of a native bug.
    return RearDisplayAvailability.unresolved;
  }
}
