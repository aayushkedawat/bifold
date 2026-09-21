import 'package:flutter/foundation.dart';

/// Whether the platform supports something, does not, or has not said yet.
///
/// The third case is the point. A boolean cannot tell "this device has no
/// hinge" apart from "nothing has reported a hinge yet", and at startup those
/// have very different consequences for a layout.
enum CapabilityStatus {
  /// The platform exposes this, and `bifold` can reach it.
  supported,

  /// The platform authoritatively does not expose this.
  ///
  /// Only a static platform query produces this. Never having observed
  /// something is not evidence that it is absent.
  unsupported,

  /// Not established yet.
  ///
  /// Either resolution has not finished, or the only signal available is
  /// observational and nothing has been observed.
  unknown;

  /// Decodes a status from its platform channel spelling.
  ///
  /// Anything unrecognised decodes to [CapabilityStatus.unknown], so a newer
  /// native build cannot make an older Dart one claim more than it knows.
  static CapabilityStatus fromName(String? name) => switch (name) {
        'supported' => CapabilityStatus.supported,
        'unsupported' => CapabilityStatus.unsupported,
        _ => CapabilityStatus.unknown,
      };
}

/// A thing a device may or may not be able to do.
///
/// Used with [BifoldCapabilities.statusOf] to read a capability
/// programmatically. The whole set is defined here even where no platform can
/// produce one yet: adding a value later would break exhaustive `switch`
/// statements in code that uses this package.
enum FoldFeature {
  /// The device has a fold or hinge, whatever position it is in now.
  fold,

  /// The platform exposes a hinge angle source.
  hingeAngle,

  /// The platform can report a part-way-open posture.
  halfOpenedPosture,

  /// The app can show content on the display facing the rear camera.
  rearDisplay,

  /// There is a secondary display the app can run on while folded shut.
  coverDisplay,

  /// The platform reports keep-out regions with bounds.
  reservedRegions,

  /// The fold can divide the window into two separate areas.
  separatingFold,

  /// The fold can hide content underneath it.
  foldOcclusion;

  /// Decodes a feature from its platform channel spelling, or null.
  static FoldFeature? fromName(String? name) {
    for (final FoldFeature feature in FoldFeature.values) {
      if (feature.name == name) {
        return feature;
      }
    }
    return null;
  }
}

/// The broad shape of a folding device.
///
/// Metadata about the device rather than a capability: it describes what the
/// hardware is, not what an app may do with it. Reported as
/// [FoldFormFactor.unknown] unless there is real evidence — fold orientation
/// alone cannot tell one flexible display from two physical ones.
enum FoldFormFactor {
  /// Not a folding device.
  none,

  /// Folds along a vertical hinge, opening like a book into a larger display.
  book,

  /// Folds along a horizontal hinge, closing into a smaller square.
  flip,

  /// Two physical displays with a gap between them.
  dualScreen,

  /// Not established.
  unknown;

  /// Decodes a form factor from its platform channel spelling.
  static FoldFormFactor fromName(String? name) => switch (name) {
        'none' => FoldFormFactor.none,
        'book' => FoldFormFactor.book,
        'flip' => FoldFormFactor.flip,
        'dualScreen' => FoldFormFactor.dualScreen,
        _ => FoldFormFactor.unknown,
      };
}

/// A way of putting app content on a display other than the main one.
///
/// The two are semantically different and a device may offer either, both or
/// neither.
enum RearDisplayMode {
  /// Content appears on the second display while the app stays on the first.
  ///
  /// This is what the foldable iPhone's camera capture accessory does, and
  /// what Android calls presenting on an area.
  presentation,

  /// The whole app moves to the second display.
  ///
  /// Android only; the foldable iPhone has no equivalent.
  transfer;

  /// Decodes a mode from its platform channel spelling, or null.
  static RearDisplayMode? fromName(String? name) => switch (name) {
        'presentation' => RearDisplayMode.presentation,
        'transfer' => RearDisplayMode.transfer,
        _ => null,
      };
}

/// What is known about one capability, and where that knowledge came from.
///
/// Kept separate from the status so diagnostics can improve without changing
/// the public surface.
@immutable
class CapabilityEvidence {
  /// Creates evidence for a capability.
  const CapabilityEvidence({required this.status, this.source});

  /// Nothing known, from nowhere.
  static const CapabilityEvidence unknown = CapabilityEvidence(
    status: CapabilityStatus.unknown,
  );

  /// Decodes evidence from a platform channel map.
  factory CapabilityEvidence.fromMap(Map<Object?, Object?> map) =>
      CapabilityEvidence(
        status: CapabilityStatus.fromName(map['status'] as String?),
        source: map['source'] as String?,
      );

  /// What is known.
  final CapabilityStatus status;

  /// Which platform signal said so, for diagnostics.
  ///
  /// A stable-ish identifier such as `android.feature.hinge_angle`. Never
  /// parse it; it is for humans reading a bug report.
  final String? source;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CapabilityEvidence &&
          other.status == status &&
          other.source == source;

  @override
  int get hashCode => Object.hash(status, source);

  @override
  String toString() => 'CapabilityEvidence(${status.name}'
      '${source == null ? '' : ', $source'})';
}

/// What this device can do, as opposed to what it is doing right now.
///
/// Capabilities answer "could this ever happen here?". `FoldInfo` answers
/// "what is happening now?". Keeping them apart matters: a foldable folded
/// shut still *has* a fold, and a hinge sensor that is present but silent is a
/// missing reading, not a missing sensor.
///
/// Read it with `Bifold.capabilitiesOf(context)` in a widget, or
/// `Bifold.capabilities` outside one.
@immutable
class BifoldCapabilities {
  /// Creates a capability set from explicit evidence.
  const BifoldCapabilities({
    required Map<FoldFeature, CapabilityEvidence> evidence,
    required this.formFactor,
    required this.rearDisplayModes,
    required this.isResolved,
    Map<String, Object?> raw = const <String, Object?>{},
  })  : _evidence = evidence,
        _raw = raw;

  /// Nothing established yet.
  ///
  /// Every status is [CapabilityStatus.unknown] and [isResolved] is false.
  /// This is what the synchronous getter reports before the platform has
  /// answered, so a false `hasFold` at startup never means "definitely not a
  /// foldable".
  static const BifoldCapabilities unresolved = BifoldCapabilities(
    evidence: <FoldFeature, CapabilityEvidence>{},
    formFactor: FoldFormFactor.unknown,
    rearDisplayModes: <RearDisplayMode>{},
    isResolved: false,
  );

  /// Established: this device folds in no way at all.
  ///
  /// Every status is [CapabilityStatus.unsupported] and [isResolved] is true.
  /// Reported on platforms with no fold support of any kind.
  static const BifoldCapabilities none = BifoldCapabilities(
    evidence: <FoldFeature, CapabilityEvidence>{
      FoldFeature.fold: CapabilityEvidence(
        status: CapabilityStatus.unsupported,
        source: 'bifold.no_platform_implementation',
      ),
      FoldFeature.hingeAngle: CapabilityEvidence(
        status: CapabilityStatus.unsupported,
        source: 'bifold.no_platform_implementation',
      ),
      FoldFeature.halfOpenedPosture: CapabilityEvidence(
        status: CapabilityStatus.unsupported,
        source: 'bifold.no_platform_implementation',
      ),
      FoldFeature.rearDisplay: CapabilityEvidence(
        status: CapabilityStatus.unsupported,
        source: 'bifold.no_platform_implementation',
      ),
      FoldFeature.coverDisplay: CapabilityEvidence(
        status: CapabilityStatus.unsupported,
        source: 'bifold.no_platform_implementation',
      ),
      FoldFeature.reservedRegions: CapabilityEvidence(
        status: CapabilityStatus.unsupported,
        source: 'bifold.no_platform_implementation',
      ),
      FoldFeature.separatingFold: CapabilityEvidence(
        status: CapabilityStatus.unsupported,
        source: 'bifold.no_platform_implementation',
      ),
      FoldFeature.foldOcclusion: CapabilityEvidence(
        status: CapabilityStatus.unsupported,
        source: 'bifold.no_platform_implementation',
      ),
    },
    formFactor: FoldFormFactor.none,
    rearDisplayModes: <RearDisplayMode>{},
    isResolved: true,
  );

  /// Decodes capabilities from a platform channel map.
  ///
  /// Unrecognised features and statuses are dropped or decoded as unknown
  /// rather than throwing, so a newer native build degrades to less
  /// information instead of failing.
  factory BifoldCapabilities.fromMap(Map<Object?, Object?> map) {
    final Map<FoldFeature, CapabilityEvidence> evidence =
        <FoldFeature, CapabilityEvidence>{};
    final Object? rawFeatures = map['features'];
    if (rawFeatures is Map<Object?, Object?>) {
      for (final MapEntry<Object?, Object?> entry in rawFeatures.entries) {
        final FoldFeature? feature = FoldFeature.fromName(entry.key as String?);
        final Object? value = entry.value;
        if (feature != null && value is Map<Object?, Object?>) {
          evidence[feature] = CapabilityEvidence.fromMap(value);
        }
      }
    }

    final Set<RearDisplayMode> modes = <RearDisplayMode>{};
    final Object? rawModes = map['rearDisplayModes'];
    if (rawModes is List) {
      for (final Object? entry in rawModes) {
        final RearDisplayMode? mode = RearDisplayMode.fromName(
          entry as String?,
        );
        if (mode != null) {
          modes.add(mode);
        }
      }
    }

    return BifoldCapabilities(
      evidence: Map<FoldFeature, CapabilityEvidence>.unmodifiable(evidence),
      formFactor: FoldFormFactor.fromName(map['formFactor'] as String?),
      rearDisplayModes: Set<RearDisplayMode>.unmodifiable(modes),
      isResolved: map['isResolved'] == true,
      raw: <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in map.entries)
          if (entry.key is String) entry.key! as String: entry.value,
      },
    );
  }

  final Map<FoldFeature, CapabilityEvidence> _evidence;
  final Map<String, Object?> _raw;

  /// The shape of the device. Metadata, not a capability.
  final FoldFormFactor formFactor;

  /// The ways this device can put content on a second display.
  ///
  /// Empty when it cannot, or when that is not yet established. Check
  /// [hasRearDisplay] to tell those apart.
  final Set<RearDisplayMode> rearDisplayModes;

  /// Whether the platform has finished answering.
  ///
  /// False only for [unresolved]. While false, every `hasX` getter is false
  /// because nothing is known — not because the answer is no.
  final bool isResolved;

  /// What is known about [feature], and where it came from.
  CapabilityEvidence evidenceOf(FoldFeature feature) =>
      _evidence[feature] ?? CapabilityEvidence.unknown;

  /// What is known about [feature].
  ///
  /// Prefer this to the `hasX` getters wherever "not established" needs
  /// different handling from "no".
  CapabilityStatus statusOf(FoldFeature feature) => evidenceOf(feature).status;

  /// Which platform signal established [feature], for diagnostics.
  ///
  /// Null when nothing has. Never parse it.
  String? sourceOf(FoldFeature feature) => evidenceOf(feature).source;

  /// The raw platform payload.
  ///
  /// An escape hatch so an app can read a capability added by a newer native
  /// build than this Dart code knows about. Prefer the typed getters.
  Map<String, Object?> get raw => Map<String, Object?>.unmodifiable(_raw);

  bool _yes(FoldFeature feature) =>
      statusOf(feature) == CapabilityStatus.supported;

  /// Whether this device has a fold, in any position including shut.
  bool get hasFold => _yes(FoldFeature.fold);

  /// Whether the platform exposes a hinge angle source.
  ///
  /// True describes the *source*, not a reading. `FoldInfo.hingeAngle` can
  /// still be null while this is true: a sensor may be present and silent.
  bool get hasHingeAngle => _yes(FoldFeature.hingeAngle);

  /// Whether the platform can report a part-way-open posture.
  bool get hasHalfOpenedPosture => _yes(FoldFeature.halfOpenedPosture);

  /// Whether the app can put content on the display facing the rear camera.
  bool get hasRearDisplay => _yes(FoldFeature.rearDisplay);

  /// Whether there is a secondary display the app can run on while shut.
  bool get hasCoverDisplay => _yes(FoldFeature.coverDisplay);

  /// Whether the platform reports keep-out regions with bounds.
  bool get hasReservedRegions => _yes(FoldFeature.reservedRegions);

  /// Whether the fold can divide the window into two areas.
  bool get hasSeparatingFold => _yes(FoldFeature.separatingFold);

  /// Whether the fold can hide content beneath it.
  bool get hasFoldOcclusion => _yes(FoldFeature.foldOcclusion);

  /// A copy with [feature] set to [evidence].
  ///
  /// Used by the resolver and by tests; apps read capabilities rather than
  /// building them.
  BifoldCapabilities withEvidence(
    FoldFeature feature,
    CapabilityEvidence evidence,
  ) =>
      BifoldCapabilities(
        evidence: Map<FoldFeature, CapabilityEvidence>.unmodifiable(
          <FoldFeature, CapabilityEvidence>{..._evidence, feature: evidence},
        ),
        formFactor: formFactor,
        rearDisplayModes: rearDisplayModes,
        isResolved: isResolved,
        raw: _raw,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BifoldCapabilities &&
          other.formFactor == formFactor &&
          other.isResolved == isResolved &&
          setEquals(other.rearDisplayModes, rearDisplayModes) &&
          mapEquals(other._evidence, _evidence);

  @override
  int get hashCode => Object.hash(
        formFactor,
        isResolved,
        Object.hashAll(rearDisplayModes),
        Object.hashAll(
          <Object?>[
            for (final FoldFeature feature in FoldFeature.values)
              _evidence[feature],
          ],
        ),
      );

  @override
  String toString() {
    if (!isResolved) {
      return 'BifoldCapabilities(unresolved)';
    }
    final Iterable<String> yes = FoldFeature.values
        .where(_yes)
        .map((FoldFeature feature) => feature.name);
    return 'BifoldCapabilities(${formFactor.name}, '
        '${yes.isEmpty ? 'nothing supported' : yes.join(', ')})';
  }
}

/// Combines capability reports over time into one answer.
///
/// The rules it enforces, which are the whole reason this is not just the
/// latest payload:
///
/// * **Observation is evidence for, never against.** Seeing something moves
///   [CapabilityStatus.unknown] to [CapabilityStatus.supported]. Not seeing it
///   moves nothing.
/// * **Supported is sticky.** A foldable folded shut reports no fold at all,
///   so a later report must not be allowed to take a capability away.
/// * **Only an authoritative static signal produces
///   [CapabilityStatus.unsupported].**
///
/// Pure Dart with no platform imports, so every rule above is unit-testable
/// without a device.
class CapabilityResolver {
  BifoldCapabilities _current = BifoldCapabilities.unresolved;

  /// Everything established so far.
  BifoldCapabilities get current => _current;

  /// Folds a fresh platform report into what is already known.
  ///
  /// Returns the combined result, which is also available from [current].
  BifoldCapabilities absorb(BifoldCapabilities incoming) {
    final Map<FoldFeature, CapabilityEvidence> merged =
        <FoldFeature, CapabilityEvidence>{};

    for (final FoldFeature feature in FoldFeature.values) {
      final CapabilityEvidence held = _current.evidenceOf(feature);
      final CapabilityEvidence fresh = incoming.evidenceOf(feature);
      merged[feature] = _merge(held, fresh);
    }

    _current = BifoldCapabilities(
      evidence: Map<FoldFeature, CapabilityEvidence>.unmodifiable(merged),
      // A known shape is never replaced by an unknown one: folding a device
      // shut stops the platform describing its shape, it does not change it.
      formFactor: incoming.formFactor == FoldFormFactor.unknown
          ? _current.formFactor
          : incoming.formFactor,
      rearDisplayModes: Set<RearDisplayMode>.unmodifiable(
        <RearDisplayMode>{
          ..._current.rearDisplayModes,
          ...incoming.rearDisplayModes,
        },
      ),
      isResolved: _current.isResolved || incoming.isResolved,
      raw: incoming.raw.isEmpty ? _current.raw : incoming.raw,
    );
    return _current;
  }

  static CapabilityEvidence _merge(
    CapabilityEvidence held,
    CapabilityEvidence fresh,
  ) {
    // Sticky: once proven present, a thing does not stop existing because the
    // device was folded shut.
    if (held.status == CapabilityStatus.supported) {
      return held;
    }
    // A positive answer always wins over not knowing, or over an earlier
    // negative that has now been contradicted.
    if (fresh.status == CapabilityStatus.supported) {
      return fresh;
    }
    // Absence of a report is not a report of absence. The status stays
    // unknown, but a fresh report that explains *why* it is unknown is better
    // diagnostics than the placeholder it replaces.
    if (fresh.status == CapabilityStatus.unknown) {
      return fresh.source != null ? fresh : held;
    }
    return fresh;
  }

  /// Forgets everything. Tests only.
  @visibleForTesting
  void reset() {
    _current = BifoldCapabilities.unresolved;
  }
}
