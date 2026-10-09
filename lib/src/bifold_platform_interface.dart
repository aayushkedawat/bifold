import 'package:flutter/foundation.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'capabilities.dart';
import 'method_channel_bifold.dart';
import 'models.dart';
import 'rear_display.dart';

/// The interface every platform implementation of `bifold` satisfies.
///
/// The default implementation, [MethodChannelBifold], talks to the iOS plugin.
/// On every other platform the channel simply has no handler, and the default
/// implementation reports [FoldInfo.unsupported] rather than failing.
///
/// Tests can replace [instance] to supply fold states without a device. Prefer
/// `BifoldScope.fake` for widget tests; replacing the platform instance is for
/// exercising the plumbing itself.
abstract class BifoldPlatform extends PlatformInterface {
  /// Constructs a [BifoldPlatform].
  BifoldPlatform() : super(token: _token);

  static final Object _token = Object();

  static BifoldPlatform _instance = MethodChannelBifold();

  /// The current platform implementation.
  static BifoldPlatform get instance => _instance;

  /// Replaces the platform implementation.
  ///
  /// Platform implementations set this when they register themselves.
  static set instance(BifoldPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Puts a fresh [MethodChannelBifold] back in [instance]. Tests only.
  ///
  /// Installing a fake was a one-way door: the default implementation is not
  /// exported, so a test that replaced [instance] left every later test in the
  /// same file stuck with the fake. It also discards the default
  /// implementation's cached streams and accumulated capability evidence,
  /// which are deliberately process-lifetime in production — several
  /// `BifoldScope`s share one native subscription, and a capability once
  /// proven stays proven — and are exactly what makes a second test in one
  /// file see the first test's leftovers.
  @visibleForTesting
  static void debugResetInstance() {
    _instance = MethodChannelBifold();
  }

  /// Reads the current fold state once.
  ///
  /// Returns [FoldInfo.unsupported] on platforms without fold support. Both
  /// reserved regions and the hinge angle arrive asynchronously after the
  /// platform's first layout pass, so an early call can legitimately report
  /// neither on a device that has both; prefer [foldInfoStream] over polling
  /// this.
  Future<FoldInfo> getFoldInfo() {
    throw UnimplementedError('getFoldInfo() has not been implemented.');
  }

  /// Describes the fold APIs the running OS exposes.
  ///
  /// Reached publicly through `Bifold.debugDescribeNativeApi()`. Named in
  /// prose rather than linked because the platform interface deliberately does
  /// not depend on the widget layer.
  Future<String?> debugDescribeNativeApi() {
    throw UnimplementedError(
      'debugDescribeNativeApi() has not been implemented.',
    );
  }

  /// Reads what this device can do, once.
  ///
  /// Returns [BifoldCapabilities.none] on platforms with no implementation.
  /// Capabilities can improve as the platform reports more, so prefer
  /// [capabilitiesStream] where that matters.
  Future<BifoldCapabilities> getCapabilities() {
    throw UnimplementedError('getCapabilities() has not been implemented.');
  }

  /// Emits capabilities as they are established.
  ///
  /// Emits on listen, then whenever something new is learned. A capability
  /// never moves from supported back to unsupported.
  Stream<BifoldCapabilities> capabilitiesStream() {
    throw UnimplementedError('capabilitiesStream() has not been implemented.');
  }

  /// Emits the fold state whenever it changes.
  ///
  /// The stream emits the current state on listen, then again on every hinge
  /// change, display change, and reserved-region update. On unsupported
  /// platforms it emits [FoldInfo.unsupported] once and stays open.
  Stream<FoldInfo> foldInfoStream() {
    throw UnimplementedError('foldInfoStream() has not been implemented.');
  }

  /// Reads the status of every rear-display mode once.
  ///
  /// Returns [RearDisplayAvailability.none] where there is no second display,
  /// and [RearDisplayAvailability.unresolved] where the platform is present
  /// but could not answer.
  ///
  /// Rear display routes through this interface rather than straight to a
  /// channel so that it can be faked. It is the most complex thing in the
  /// package and the hardest to reach on real hardware, so a downstream test
  /// has to be able to drive it without encoding a channel name this package
  /// is free to change.
  Future<RearDisplayAvailability> rearDisplayStatus() {
    throw UnimplementedError('rearDisplayStatus() has not been implemented.');
  }

  /// Emits rear-display availability whenever the system changes its mind.
  ///
  /// Emits on listen. An implementation must emit a settled value rather than
  /// nothing where there is no second display, so a UI can bind to this
  /// unconditionally instead of branching on the platform first.
  Stream<RearDisplayAvailability> rearDisplayAvailabilityStream() {
    throw UnimplementedError(
      'rearDisplayAvailabilityStream() has not been implemented.',
    );
  }

  /// Puts [entrypoint]'s content on the second display.
  ///
  /// [entrypoint] names a top-level function annotated
  /// `@pragma('vm:entry-point')`; [libraryUri] names the library it lives in,
  /// and defaults to the app's own `main.dart`.
  ///
  /// Returns whether a session started. False means the system declined,
  /// which is a normal answer rather than a failure.
  Future<bool> presentOnRearDisplay({
    required String entrypoint,
    String? libraryUri,
  }) {
    throw UnimplementedError(
      'presentOnRearDisplay() has not been implemented.',
    );
  }

  /// Moves the whole app to the display facing the rear camera.
  ///
  /// Returns whether it moved. No platform other than Android has an
  /// equivalent, so false is the expected answer almost everywhere.
  Future<bool> transferToRearDisplay() {
    throw UnimplementedError(
      'transferToRearDisplay() has not been implemented.',
    );
  }

  /// Ends whichever rear-display session is running.
  ///
  /// Must succeed when none is: tearing down is best-effort, and an app
  /// disposing a camera screen does not know whether the system already
  /// ended the session itself.
  Future<void> endRearDisplay() {
    throw UnimplementedError('endRearDisplay() has not been implemented.');
  }
}
