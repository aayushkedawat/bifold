## 0.1.0-dev.1

Not yet released.

Fold awareness for the foldable iPhone.

**Fold state**

* `FoldInfo` with `pose`, `hingeAngle` / `hingeAngleDegrees`, `display`,
  `regions`, `division`, `horizontalSizeClass`, `verticalSizeClass`,
  `isRegular` and `verticalBarEdge`.
* `BifoldScope` and `Bifold.of(context)` to read it in the widget tree, plus
  `Bifold.current` and `Bifold.stream` outside it.
* `pose` comes from the platform's own `UIHingeStatus`, falling back to
  region-derived state until the first hinge update lands.

**Layout**

* `BifoldSplit`, a two-pane layout that aligns to the fold and falls back to
  stacking when there is nothing to split across.
* `BifoldGrid`, which never draws a tile across the crease.
* `bifoldAnchorPoint`, so dialogs and sheets land in a half rather than on the
  fold.
* `BifoldDisplayFeatures`, an opt-in bridge that republishes the fold as
  `MediaQuery.displayFeatures` for packages built against Android foldables.
  It steps aside automatically once the engine populates that field natively.

**Platform geometry**

* `BifoldArrangement.measure`, which reports where the platform's own split
  arrangement would place two panes, measured from a real arrangement rather
  than modelled.

**Camera**

* `BifoldCaptureAccessory`, which presents app content on the outer display
  during camera capture, in its own Flutter engine.

**Tooling**

* `BifoldDebugOverlay`, which draws the reserved regions the platform reports.
* `FoldInfoFakes`, so fold-aware layouts can be tested on any machine with no
  simulator and no iOS SDK.

**Platforms**

* iOS only. Every other platform reports `FoldInfo.unsupported` and never
  throws.
* Builds on Xcode 26.x and 27.0 — the iOS 27.1 SDK is not required, because
  fold symbols are resolved through the Objective-C runtime.
