import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

/// The version of the platform channel payload this build of the package
/// understands.
///
/// The native side stamps every message with a `version` key. If a future
/// native build sends a higher version, [FoldInfo.fromMap] still decodes the
/// fields it recognises rather than failing, so a version skew degrades to
/// partial information instead of an exception.
const int kBifoldPayloadVersion = 1;

/// Which physical display the app is currently presented on.
enum FoldDisplay {
  /// The smaller cover display, available while the device is folded shut.
  ///
  /// This display behaves like a conventional phone screen: a compact
  /// horizontal size class, and no reserved regions.
  outer,

  /// The large inner display, available while the device is open.
  ///
  /// Note that this display does not honour an app's supported interface
  /// orientations. Lay out against size classes, not orientation.
  inner,

  /// The device is not foldable, or the current display could not be
  /// determined.
  none;

  /// Decodes a [FoldDisplay] from its platform channel spelling.
  ///
  /// Returns [FoldDisplay.none] for anything unrecognised, so that a newer
  /// native build cannot crash an older Dart one.
  static FoldDisplay fromName(String? name) => switch (name) {
    'outer' => FoldDisplay.outer,
    'inner' => FoldDisplay.inner,
    _ => FoldDisplay.none,
  };
}

/// How far the device is folded.
///
/// These cases mirror the platform's own hinge status exactly. Postures such
/// as "book" or "tabletop" are deliberately absent: they are Android foldable
/// vocabulary, and the foldable iPhone does not report them. Deriving such a
/// posture from a hinge angle is a decision for the app, not for this package.
enum FoldPose {
  /// The device is shut. The outer display is the active one, and no reserved
  /// regions are reported.
  closed,

  /// The device is between shut and flat, so the inner display is creased.
  ///
  /// This is the only pose in which a [RegionKind.division] is reported.
  partiallyOpen,

  /// The device is open flat.
  fullyOpen,

  /// The pose is not known: a non-foldable device, an OS without the fold
  /// APIs, or a report that arrived before the first hinge update.
  unknown;

  /// Decodes a [FoldPose] from its platform channel spelling.
  ///
  /// Returns [FoldPose.unknown] for anything unrecognised.
  static FoldPose fromName(String? name) => switch (name) {
    'closed' => FoldPose.closed,
    'partiallyOpen' => FoldPose.partiallyOpen,
    'fullyOpen' => FoldPose.fullyOpen,
    _ => FoldPose.unknown,
  };
}

/// What a [FoldRegion] represents.
enum RegionKind {
  /// The fold itself: the crease running across the inner display.
  ///
  /// A division does not obstruct drawing. Content may be painted across it,
  /// but interactive controls and text should avoid it.
  division,

  /// Hardware that obstructs part of the display, such as the under-display
  /// front camera.
  ///
  /// An occlusion is typically inactive until the hardware behind it is in
  /// use, so check [FoldRegion.isActive] before laying out around it.
  occlusion,

  /// A region kind this version of the package does not recognise.
  ///
  /// Present so that a newer OS reporting a new kind degrades to "something is
  /// here, avoid it" rather than being dropped silently.
  unknown;

  /// Decodes a [RegionKind] from its platform channel spelling.
  static RegionKind fromName(String? name) => switch (name) {
    'division' => RegionKind.division,
    'occlusion' => RegionKind.occlusion,
    _ => RegionKind.unknown,
  };
}

/// An area of the display claimed by hardware.
///
/// A reserved region is *not* part of the safe area; it is a separate concept.
/// The safe area keeps content clear of system UI, while a reserved region
/// keeps content clear of the hardware itself.
///
/// Regions are reported in logical pixels relative to the Flutter view. On iOS
/// a logical pixel and a UIKit point are the same unit, so no scaling is
/// applied when crossing the channel.
///
/// {@template bifold.no_caching}
/// Never cache a region across layout passes. Regions arrive after the first
/// layout pass and change as the device folds, so read them from the current
/// [FoldInfo] every build.
/// {@endtemplate}
@immutable
class FoldRegion {
  /// Creates a region description.
  const FoldRegion({
    required this.kind,
    required this.frame,
    required this.margins,
    required this.isActive,
  });

  /// Decodes a region from a platform channel map.
  ///
  /// Missing or malformed numbers fall back to zero rather than throwing, so
  /// that one bad region cannot take down the whole stream.
  factory FoldRegion.fromMap(Map<Object?, Object?> map) {
    double number(String key) {
      final value = map[key];
      return value is num ? value.toDouble() : 0.0;
    }

    return FoldRegion(
      kind: RegionKind.fromName(map['kind'] as String?),
      frame: Rect.fromLTRB(
        number('left'),
        number('top'),
        number('right'),
        number('bottom'),
      ),
      margins: EdgeInsets.fromLTRB(
        number('marginLeft'),
        number('marginTop'),
        number('marginRight'),
        number('marginBottom'),
      ),
      isActive: map['isActive'] == true,
    );
  }

  /// What this region is.
  final RegionKind kind;

  /// The whole area interactive content should avoid, in logical pixels
  /// relative to the Flutter view.
  ///
  /// **This already includes [margins].** The platform reports the frame with
  /// the clearance built in, so it is the rectangle to lay out around
  /// directly — do not add the margins again. Use [reservedRect] for the
  /// hardware itself.
  ///
  /// A [RegionKind.division] may be zero-width: the display creases without a
  /// physical gap. Use [isSeparating] to distinguish a region that splits the
  /// display from one that merely marks a line on it.
  final Rect frame;

  /// How much of [frame] is clearance rather than hardware.
  ///
  /// These margins are *contained in* [frame], not added to it. They exist so
  /// that a caller can tell the two apart: content which must stay legible and
  /// tappable should clear all of [frame], while purely decorative content may
  /// run into the margins and stop at [reservedRect].
  final EdgeInsets margins;

  /// Whether the hardware behind this region is currently in use.
  ///
  /// Most regions are inactive by default. An inactive occlusion still
  /// describes where the hardware is, which is why it is reported at all, but
  /// laying out around it while it is inactive wastes space.
  final bool isActive;

  /// The hardware itself: [frame] with its [margins] removed.
  ///
  /// This is the crease or the cutout with no clearance around it. Decorative
  /// content may run up to this edge; interactive content should stop at
  /// [frame].
  Rect get reservedRect => margins.deflateRect(frame);

  /// Whether this region actually divides the display into two parts.
  ///
  /// True when the region spans the full width or the full height of
  /// [viewSize] and has a non-zero thickness across that span. A zero-width
  /// crease reports `false`, because content can be laid out across it.
  bool isSeparating(Size viewSize) {
    const double tolerance = 1.0;
    final bool spansHorizontally =
        frame.left <= tolerance && frame.right >= viewSize.width - tolerance;
    final bool spansVertically =
        frame.top <= tolerance && frame.bottom >= viewSize.height - tolerance;
    return (spansHorizontally && frame.height > 0) ||
        (spansVertically && frame.width > 0);
  }

  /// Whether this region runs across the display horizontally, splitting it
  /// into a top and a bottom part.
  ///
  /// Only meaningful for a region where [isSeparating] is true.
  bool get isHorizontal => frame.width >= frame.height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoldRegion &&
          other.kind == kind &&
          other.frame == frame &&
          other.margins == margins &&
          other.isActive == isActive;

  @override
  int get hashCode => Object.hash(kind, frame, margins, isActive);

  @override
  String toString() =>
      'FoldRegion(${kind.name}, $frame, margins: $margins, '
      'isActive: $isActive)';
}

/// A complete description of the device's fold state at one moment.
///
/// Obtain the current value with `Bifold.of(context)`, which rebuilds the
/// calling widget whenever the state changes.
///
/// {@macro bifold.no_caching}
@immutable
class FoldInfo {
  /// Creates a fold state description.
  const FoldInfo({
    required this.isFoldable,
    required this.display,
    required this.pose,
    required this.regions,
  });

  /// The state reported on every device and platform without fold support.
  ///
  /// This is what non-foldable iPhones, older iOS versions, iPad, Android, web
  /// and desktop all report, and what widget tests see unless they supply
  /// their own. Nothing in this package throws when the platform is
  /// unsupported; it reports this instead.
  static const FoldInfo unsupported = FoldInfo(
    isFoldable: false,
    display: FoldDisplay.none,
    pose: FoldPose.unknown,
    regions: <FoldRegion>[],
  );

  /// Decodes fold state from a platform channel map.
  ///
  /// Unrecognised enum spellings decode to their `unknown`/`none` case and
  /// malformed regions are dropped, so a native build newer than this package
  /// degrades rather than throwing.
  factory FoldInfo.fromMap(Map<Object?, Object?> map) {
    final Object? rawRegions = map['regions'];
    final List<FoldRegion> regions;
    if (rawRegions is List) {
      regions = <FoldRegion>[
        for (final Object? entry in rawRegions)
          if (entry is Map<Object?, Object?>) FoldRegion.fromMap(entry),
      ];
    } else {
      regions = const <FoldRegion>[];
    }

    return FoldInfo(
      isFoldable: map['isFoldable'] == true,
      display: FoldDisplay.fromName(map['display'] as String?),
      pose: FoldPose.fromName(map['pose'] as String?),
      regions: List<FoldRegion>.unmodifiable(regions),
    );
  }

  /// Whether the device has a fold this package can report on.
  ///
  /// False on every non-foldable device, and also on a foldable running an OS
  /// without the fold APIs.
  final bool isFoldable;

  /// Which display the app is currently presented on.
  final FoldDisplay display;

  /// How far the device is folded.
  final FoldPose pose;

  /// Every reserved region currently reported for the Flutter view, active or
  /// not.
  ///
  /// Empty while the device is closed, on the outer display, and on
  /// unsupported platforms. This list is unmodifiable.
  ///
  /// {@macro bifold.no_caching}
  final List<FoldRegion> regions;

  /// The regions where [FoldRegion.isActive] is true.
  Iterable<FoldRegion> get activeRegions =>
      regions.where((FoldRegion region) => region.isActive);

  /// The active fold, if the display is currently creased.
  ///
  /// Null when the device is flat, folded shut, on the outer display, or not
  /// foldable. A division is only reported while the pose is
  /// [FoldPose.partiallyOpen].
  FoldRegion? get division {
    for (final FoldRegion region in regions) {
      if (region.kind == RegionKind.division && region.isActive) {
        return region;
      }
    }
    return null;
  }

  /// Creates a copy with the given fields replaced.
  FoldInfo copyWith({
    bool? isFoldable,
    FoldDisplay? display,
    FoldPose? pose,
    List<FoldRegion>? regions,
  }) => FoldInfo(
    isFoldable: isFoldable ?? this.isFoldable,
    display: display ?? this.display,
    pose: pose ?? this.pose,
    regions: regions ?? this.regions,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoldInfo &&
          other.isFoldable == isFoldable &&
          other.display == display &&
          other.pose == pose &&
          listEquals(other.regions, regions);

  @override
  int get hashCode =>
      Object.hash(isFoldable, display, pose, Object.hashAll(regions));

  @override
  String toString() =>
      'FoldInfo(isFoldable: $isFoldable, display: ${display.name}, '
      'pose: ${pose.name}, regions: ${regions.length})';
}
