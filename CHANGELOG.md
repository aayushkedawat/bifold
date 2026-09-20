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
* iOS support only. Every other platform reports `FoldInfo.unsupported`.

Known limitations, in full in the README:

* The region coordinate space is not yet verified on an opened device.
* Hinge angle is not exposed; pose is derived from the reported regions.
* Nothing has been verified on physical hardware, which does not yet exist.
