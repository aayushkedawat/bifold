import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_bifold.dart';
import 'models.dart';

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

  /// Describes the fold APIs the running OS exposes. See
  /// [Bifold.debugDescribeNativeApi].
  Future<String?> debugDescribeNativeApi() {
    throw UnimplementedError(
      'debugDescribeNativeApi() has not been implemented.',
    );
  }

  /// Emits the fold state whenever it changes.
  ///
  /// The stream emits the current state on listen, then again on every hinge
  /// change, display change, and reserved-region update. On unsupported
  /// platforms it emits [FoldInfo.unsupported] once and stays open.
  Stream<FoldInfo> foldInfoStream() {
    throw UnimplementedError('foldInfoStream() has not been implemented.');
  }
}
