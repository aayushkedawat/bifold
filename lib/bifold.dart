/// Fold awareness for Flutter apps on the foldable iPhone.
///
/// Wrap the app in a [BifoldScope], then read the current state anywhere below
/// it with `Bifold.of(context)`:
///
/// ```dart
/// void main() => runApp(const BifoldScope(child: MyApp()));
///
/// // ...somewhere below:
/// final info = Bifold.of(context);
/// if (info.division != null) {
///   // The display is creased right now.
/// }
/// ```
///
/// [BifoldSplit] lays two panes out on either side of the fold, and
/// [BifoldDebugOverlay] draws the regions the platform is reporting so they
/// can be seen rather than guessed at.
///
/// Two different questions have two different answers. What is the device
/// doing *now* is [FoldInfo]. What this device *can ever do* is
/// [BifoldCapabilities], read with `Bifold.capabilitiesOf(context)`:
///
/// ```dart
/// if (Bifold.capabilitiesOf(context).hasHingeAngle) {
///   // Worth building a hinge-reactive UI on this device.
/// }
/// ```
///
/// Keeping them apart matters. A foldable folded shut still has a fold, and a
/// hinge sensor that is present but silent is a missing reading rather than a
/// missing sensor.
///
/// On every platform without fold support — non-foldable phones, older iOS,
/// iPad, web and desktop — this package reports [FoldInfo.unsupported] and
/// [BifoldCapabilities.none], and never throws.
library;

// Imported as well as exported so that the doc references above resolve to
// links rather than plain text in the generated API docs.
import 'src/capabilities.dart';
import 'src/models.dart';
import 'src/widgets/bifold_debug_overlay.dart';
import 'src/widgets/bifold_scope.dart';
import 'src/widgets/bifold_split.dart';

export 'src/arrangement.dart'
    show
        ArrangementAxis,
        ArrangementMeasurement,
        ArrangementPane,
        BifoldArrangement;
export 'src/bifold_platform_interface.dart' show BifoldPlatform;
export 'src/capabilities.dart'
    show
        BifoldCapabilities,
        CapabilityEvidence,
        CapabilityResolver,
        CapabilityStatus,
        FoldFeature,
        FoldFormFactor,
        RearDisplayMode;
export 'src/capture_accessory.dart' show BifoldCaptureAccessory;
export 'src/rear_display.dart'
    show BifoldRearDisplay, RearDisplayAvailability, RearDisplayStatus;
export 'src/anchoring.dart' show bifoldAnchorPoint;
export 'src/fakes.dart'
    show BifoldCapabilityFakes, FakeBifoldPlatform, FoldInfoFakes;
export 'src/models.dart'
    show
        FoldDisplay,
        FoldInfo,
        FoldPose,
        FoldRegion,
        FoldSizeClass,
        RegionKind,
        VerticalBarEdge,
        kBifoldPayloadVersion;
export 'src/widgets/bifold_debug_overlay.dart' show BifoldDebugOverlay;
export 'src/widgets/bifold_display_features.dart' show BifoldDisplayFeatures;
export 'src/widgets/bifold_grid.dart' show BifoldGrid;
export 'src/widgets/bifold_scaffold.dart'
    show BifoldDestination, BifoldScaffold;
export 'src/widgets/bifold_scope.dart' show Bifold, BifoldScope;
export 'src/widgets/bifold_split.dart' show BifoldSplit, BifoldSplitFallback;
