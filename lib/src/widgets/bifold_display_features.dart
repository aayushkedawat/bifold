import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../models.dart';
import 'bifold_scope.dart';

/// Republishes fold state as [MediaQueryData.displayFeatures], so packages
/// built for Android foldables work on this device too.
///
/// Flutter's own `displayFeatures` are populated by the engine, and the engine
/// only does that on Android. A great many layout packages — and Flutter's own
/// [DisplayFeatureSubScreen], which positions dialogs and popups — read that
/// list and therefore see nothing here. Wrapping the app in this widget fills
/// it in from `bifold`'s own model:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => BifoldDisplayFeatures(child: child!),
///   home: const MyHomePage(),
/// )
/// ```
///
/// ## Opt in deliberately
///
/// This is **not** enabled by default, for one reason:
/// [flutter/flutter#193025](https://github.com/flutter/flutter/pull/193025) is
/// adding native `displayFeatures` on iOS. When that lands and reaches a
/// stable release, the engine will populate the same field for real, and two
/// writers would be one too many. By then this widget can simply be removed —
/// [isRedundant] reports when the engine has already done the job, and the
/// widget steps aside on its own rather than overwriting engine truth.
///
/// ## Mapping
///
/// Deliberately identical to the mapping that pull request chose, so that an
/// app which later drops this widget sees no behavioural change:
///
/// * a [RegionKind.division] becomes [ui.DisplayFeatureType.fold], not
///   `hinge`, because the inner display is continuous with no physical gap;
/// * a [RegionKind.occlusion] becomes [ui.DisplayFeatureType.cutout] with
///   state [ui.DisplayFeatureState.unknown];
/// * inactive and zero-area regions are dropped, because a display feature
///   describes something that is actually there;
/// * nothing is reported while the device is shut, because `dart:ui` has no
///   closed posture.
class BifoldDisplayFeatures extends StatelessWidget {
  /// Wraps [child] in a [MediaQuery] carrying the current fold as display
  /// features.
  const BifoldDisplayFeatures({required this.child, super.key});

  /// The subtree that should see the republished features.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final FoldInfo info = Bifold.of(context);
    final MediaQueryData data = MediaQuery.of(context);

    if (isRedundant(data)) {
      return child;
    }

    final List<ui.DisplayFeature> features = toDisplayFeatures(info);
    if (features.isEmpty) {
      return child;
    }

    return MediaQuery(
      data: data.copyWith(displayFeatures: features),
      child: child,
    );
  }

  /// Whether the engine is already reporting display features.
  ///
  /// Once the iOS embedder populates them natively, republishing would
  /// overwrite the real thing with a copy. This widget checks rather than
  /// assumes, so it keeps working correctly across that transition without a
  /// version check or a release of this package.
  static bool isRedundant(MediaQueryData data) => data.displayFeatures.isNotEmpty;

  /// Converts fold state into Flutter's display feature model.
  ///
  /// Exposed so the mapping can be tested and reused without a widget.
  static List<ui.DisplayFeature> toDisplayFeatures(FoldInfo info) {
    if (!info.isFoldable || info.pose == FoldPose.closed) {
      return const <ui.DisplayFeature>[];
    }

    final List<ui.DisplayFeature> features = <ui.DisplayFeature>[];
    for (final FoldRegion region in info.regions) {
      if (!region.isActive || region.frame.isEmpty) {
        continue;
      }
      switch (region.kind) {
        case RegionKind.division:
          features.add(
            ui.DisplayFeature(
              bounds: region.frame,
              type: ui.DisplayFeatureType.fold,
              state: _postureFor(info.pose),
            ),
          );
        case RegionKind.occlusion:
          features.add(
            ui.DisplayFeature(
              bounds: region.frame,
              type: ui.DisplayFeatureType.cutout,
              // dart:ui asserts that a cutout's state is unknown.
              state: ui.DisplayFeatureState.unknown,
            ),
          );
        case RegionKind.unknown:
          // A kind this build does not recognise has no safe mapping: calling
          // it a fold would make layouts split across it. Left out.
          break;
      }
    }
    return List<ui.DisplayFeature>.unmodifiable(features);
  }

  static ui.DisplayFeatureState _postureFor(FoldPose pose) => switch (pose) {
    FoldPose.partiallyOpen => ui.DisplayFeatureState.postureHalfOpened,
    FoldPose.fullyOpen => ui.DisplayFeatureState.postureFlat,
    // dart:ui has no closed posture, and unknown is the documented fallback.
    FoldPose.closed || FoldPose.unknown => ui.DisplayFeatureState.unknown,
  };
}
