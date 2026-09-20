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
/// On every platform without fold support — non-foldable iPhones, older iOS,
/// iPad, Android, web and desktop — this package reports
/// [FoldInfo.unsupported] and never throws.
library;

export 'src/bifold_platform_interface.dart' show BifoldPlatform;
export 'src/capture_accessory.dart' show BifoldCaptureAccessory;
export 'src/anchoring.dart' show bifoldAnchorPoint;
export 'src/fakes.dart' show FoldInfoFakes;
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
export 'src/widgets/bifold_scope.dart' show Bifold, BifoldScope;
export 'src/widgets/bifold_split.dart' show BifoldSplit, BifoldSplitFallback;
