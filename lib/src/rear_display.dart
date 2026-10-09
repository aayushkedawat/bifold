import 'dart:async';

import 'package:flutter/foundation.dart';

import 'bifold_platform_interface.dart';
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
    this.isResolved = false,
  });

  /// Nothing has reported yet.
  ///
  /// Both modes read [RearDisplayStatus.unsupported] because nothing better
  /// is known, and [isResolved] is false to say so. Hiding a control on this
  /// is premature; it is the state to show a placeholder for, or to wait on.
  static const RearDisplayAvailability unresolved = RearDisplayAvailability(
    presentation: RearDisplayStatus.unsupported,
    transfer: RearDisplayStatus.unsupported,
  );

  /// Nothing is possible, and that is settled.
  ///
  /// What every platform without support reports. Identical to [unresolved]
  /// except that [isResolved] is true, which is the difference between "this
  /// device cannot" and "nobody has said".
  static const RearDisplayAvailability none = RearDisplayAvailability(
    presentation: RearDisplayStatus.unsupported,
    transfer: RearDisplayStatus.unsupported,
    isResolved: true,
  );

  /// Decodes availability from a platform channel map.
  factory RearDisplayAvailability.fromMap(Map<Object?, Object?> map) =>
      RearDisplayAvailability(
        presentation: RearDisplayStatus.fromName(
          map['presentation'] as String?,
        ),
        transfer: RearDisplayStatus.fromName(map['transfer'] as String?),
        // Read strictly, like FoldInfo.isResolved: the platform states
        // whether it has established anything, because it is the only side
        // that knows.
        isResolved: map['isResolved'] == true,
      );

  /// Content on the second display while the app stays on the first.
  final RearDisplayStatus presentation;

  /// The whole app moving to the second display. Android only.
  final RearDisplayStatus transfer;

  /// Whether the platform has actually answered.
  ///
  /// False only on [unresolved]. While false, both statuses reading
  /// `unsupported` means "not known", not "no".
  final bool isResolved;

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
          other.transfer == transfer &&
          other.isResolved == isResolved;

  @override
  int get hashCode => Object.hash(presentation, transfer, isResolved);

  @override
  String toString() => isResolved
      ? 'RearDisplayAvailability(presentation: ${presentation.name}, '
          'transfer: ${transfer.name})'
      : 'RearDisplayAvailability(unresolved)';
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
///
/// ## Testing an app that uses this
///
/// Everything here goes through [BifoldPlatform], so `FakeBifoldPlatform`
/// drives all of it with no channel mocking:
///
/// ```dart
/// final platform = FakeBifoldPlatform(rearDisplay: RearDisplayFakes.available);
/// BifoldPlatform.instance = platform;
/// addTearDown(BifoldPlatform.debugResetInstance);
///
/// // ...then, to model the system starting and ending a session:
/// platform.emitRearDisplay(RearDisplayFakes.presenting);
/// ```
abstract final class BifoldRearDisplay {
  /// The status of both modes, updating as the system changes its mind.
  ///
  /// Emits on listen. On platforms with no support it emits
  /// [RearDisplayAvailability.none] and stays open, so a UI can bind to it
  /// unconditionally.
  static Stream<RearDisplayAvailability> get availability {
    try {
      return BifoldPlatform.instance.rearDisplayAvailabilityStream();
    } on UnimplementedError {
      return _absent;
    }
  }

  /// Reads the status of both modes once.
  static Future<RearDisplayAvailability> get current async {
    try {
      return await BifoldPlatform.instance.rearDisplayStatus();
    } on UnimplementedError {
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
      return await BifoldPlatform.instance.presentOnRearDisplay(
        entrypoint: entrypoint,
        libraryUri: libraryUri,
      );
    } on UnimplementedError {
      return false;
    }
  }

  /// Moves the whole app to the rear display.
  ///
  /// Android only. Returns false everywhere else, and on Android whenever the
  /// system is unwilling.
  static Future<bool> transferActivity() async {
    try {
      return await BifoldPlatform.instance.transferToRearDisplay();
    } on UnimplementedError {
      return false;
    }
  }

  /// Ends whichever session is running. Safe to call when none is.
  static Future<void> end() async {
    try {
      await BifoldPlatform.instance.endRearDisplay();
    } on UnimplementedError {
      // Nothing to end where nothing can start.
    }
  }

  /// What [availability] reports when the platform implementation predates
  /// rear display.
  ///
  /// A [BifoldPlatform] written before these methods existed throws
  /// [UnimplementedError] from its inherited bodies, and an app must not see
  /// that: a platform that cannot answer is, for the app's purposes, a
  /// platform with no second display. Open rather than closed, and built once
  /// per process rather than per call, because the documented contract is a
  /// stream a `StreamBuilder` can hold on to.
  static final Stream<RearDisplayAvailability> _absent = () {
    late final StreamController<RearDisplayAvailability> controller;
    controller = StreamController<RearDisplayAvailability>.broadcast(
      onListen: () => controller.add(RearDisplayAvailability.none),
    );
    return controller.stream;
  }();
}
