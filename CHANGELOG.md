## 0.1.0-dev.1

Not yet released.

First cut of fold awareness for the foldable iPhone.

* `FoldInfo`, `FoldRegion`, `FoldDisplay`, `FoldPose` and `RegionKind`, with a
  decoder that degrades rather than throwing when a newer OS sends something
  this build does not recognise.
* `BifoldScope` and `Bifold.of(context)` to read fold state in the widget tree,
  plus `Bifold.current` and `Bifold.stream` outside it.
* `BifoldSplit`, a two-pane layout that aligns to the fold and falls back to
  stacking when there is nothing to split across.
* `BifoldDebugOverlay`, which draws the reserved regions the platform reports.
* `FoldInfoFakes`, so fold-aware layouts can be tested on any machine with no
  simulator and no iOS SDK.
* `FoldInfo.hingeAngle` (radians) and `hingeAngleDegrees`, read from
  `UIHingeInteraction`. `pose` comes from the platform's own `UIHingeStatus`,
  falling back to region-derived state until the first hinge update lands.
* iOS support only. Every other platform reports `FoldInfo.unsupported`.
* Builds on Xcode 26.x and 27.0 — the iOS 27.1 SDK is not required, because
  fold symbols are resolved through the Objective-C runtime.

Known limitations, in full in the README:

* `pose` and `hingeAngle` arrive a moment after the stream is first listened
  to, because the platform delivers the initial hinge update asynchronously.
* Nothing has been verified on physical hardware, which does not yet exist,
  and the simulator has only been observed shut.
