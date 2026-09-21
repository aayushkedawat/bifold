## 0.3.0

**Added — rear display**

Content on the display that faces the rear camera, behind one API on both
platforms.

* `BifoldRearDisplay.present(entrypoint:)` runs a second Flutter engine whose
  content appears on the other display while the app stays where it is. On
  Android this is `OPERATION_PRESENT_ON_AREA`; on iOS it is the camera capture
  accessory. The entrypoint needs `@pragma('vm:entry-point')`.
* `BifoldRearDisplay.transferActivity()` moves the whole app across. Android
  only — iOS reports `unsupported` and does nothing, rather than pretending.
* `BifoldRearDisplay.availability` and `.current` report both modes with a
  four-state `RearDisplayStatus`: `unsupported`, `unavailable`, `available`,
  `active`. Four rather than a boolean because "this device cannot" and "it
  could, but not now" call for different UI — hide the control versus disable
  it.
* `BifoldRearDisplay.end()` ends whichever session is running.

`BifoldCaptureAccessory` is unchanged and still works. It remains the right
choice for iOS-specific code; `BifoldRearDisplay` is the cross-platform
surface over the same thing.

**Known limitations**

* **Ending a presentation session is unverified.** On the Android 37.2
  emulator `close()` produces no `onSessionEnded` callback and the platform
  keeps reporting the area as `active` indefinitely. The second engine is
  destroyed correctly so nothing leaks, but the status stays `active`. That
  value is passed through rather than replaced with an `available` the
  platform is not reporting. A physical device may behave correctly.
* Starting a session *is* verified: `available` to `active` with real Flutter
  content, on a `pixel_9_pro_fold` emulator.
* Nothing here has run on physical hardware, on either platform.

## 0.2.0

Android foldables are supported. The same `FoldInfo`, the same widgets and the
same tests now work on both platforms, and consumer code does not branch on
which one it is running on.

**Added — capabilities**

A device answers two different questions now. `FoldInfo` says what it is
doing; `BifoldCapabilities` says what it can ever do.

* `Bifold.capabilitiesOf(context)` in a widget, `Bifold.capabilities`
  outside one, plus `Bifold.capabilitiesStream`, `Bifold.capabilitiesReady`
  and `Bifold.initialize()`.
* `hasFold`, `hasHingeAngle`, `hasHalfOpenedPosture`, `hasRearDisplay`,
  `hasCoverDisplay`, `hasReservedRegions`, `hasSeparatingFold` and
  `hasFoldOcclusion`, on both platforms.
* Every capability is really tri-state. `statusOf(feature)` exposes
  `supported` / `unsupported` / `unknown`, because a boolean cannot tell
  "this device has no hinge" from "nothing has reported a hinge yet", and at
  startup those mean very different things. `hasX` is true only for
  `supported`.
* `BifoldCapabilities.unresolved` and `BifoldCapabilities.none` — both
  report `hasFold` false, and only one of them means no.
* `sourceOf(feature)` names the platform signal behind each answer, and
  `Bifold.diagnosticReport()` prints the lot for a bug report. Nothing is
  transmitted; it returns a string.
* `formFactor` (`book`, `flip`, `none`, `unknown`; never `dualScreen`, which
  fold orientation cannot establish) and `rearDisplayModes`.
* `FoldInfo.isResolved` and `FoldInfo.none`, for the same reason: they differ
  from `FoldInfo.unsupported` only in whether the platform has answered.
* `FakeBifoldPlatform`, so a test can drive the stream itself rather than
  reimplement a controller, and `BifoldCapabilityFakes` profiles named after
  device shapes rather than products.
* Three downstream examples under `example/lib/downstream/` — a hinge-reactive
  creature, a two-pane layout and a rear-display camera — each written with
  **no platform checks at all**, with tests covering every device shape.

**Added — Android**

* Android implementation, in Kotlin, over Jetpack WindowManager
  (`androidx.window` 1.2.0, pinned to the version Flutter's own embedding
  already resolves so the plugin cannot cause a conflict with the engine).
* `FoldInfo.pose` on Android from `FoldingFeature.State`: `FLAT` maps to
  `fullyOpen`, `HALF_OPENED` to `partiallyOpen`.
* `FoldInfo.regions` on Android from `FoldingFeature`, reported as a
  `RegionKind.division`. `isActive` follows `isSeparating`, which is the same
  thing the active division means on iOS.
* `FoldInfo.hingeAngle` on Android from `Sensor.TYPE_HINGE_ANGLE` (API 30+),
  converted from the degrees the sensor reports to the radians the API
  documents.
* `FoldInfo.isFoldable` on Android from
  `PackageManager.FEATURE_SENSOR_HINGE_ANGLE`, which answers on a **closed**
  device, where no folding feature is reported at all.
* Size classes on Android, derived from the current window against the
  Material breakpoints (600dp wide, 480dp tall). Without these `isRegular` was
  always false and `BifoldScaffold` rendered its compact layout on every
  Android device, tablets and unfolded foldables included.
* An Android target in the example app.
* `API_NOTES.md` gains an Android section: every symbol with the artifact it
  was verified against, the observed emulator behaviour, and what remains
  unverified.

**Fixed**

* No more `MissingPluginException` in the console on platforms with no native
  implementation. Every Android, web and desktop launch previously logged
  `MissingPluginException(No implementation found for method listen on channel
  dev.bifold/fold_info)` from the services library. Fold state was correct
  throughout and nothing threw, but the error looked like a broken plugin.
  `EventChannel.receiveBroadcastStream` reports its own failed `listen` through
  `FlutterError.reportError` rather than through the stream, so no error
  handling in this package could suppress it; `foldInfoStream()` now asks the
  method channel whether an implementation is registered and subscribes only if
  one is.

**Changed**

* `FoldInfo.fromMap({})` now decodes to `FoldInfo.none` rather than
  `FoldInfo.unsupported`. A payload arriving at all means the platform
  answered, and the two differ only in `isResolved`. Code comparing a decoded
  value against `FoldInfo.unsupported` will see a difference.
* `Bifold.debugDescribeNativeApi()` is deprecated in favour of
  `Bifold.diagnosticReport()`, which includes it alongside capabilities and
  current state. It still works, and is removed in 0.4.0.

**Known limitations**

* `hasCoverDisplay` is `unknown` on Android, and will probably stay that way.
  Whether an app may run on a cover display is OEM policy, and there is no
  public query behind it. Reporting `unsupported` would be a stronger claim
  than the evidence allows.
* `hasHalfOpenedPosture` is `unknown` on Android until a half-opened posture
  has actually been observed. No static signal for it exists, and never having
  seen something is not evidence it cannot happen.
* Rear display reports capability and availability only. Actually presenting
  content on the second display is not implemented on Android; the iOS capture
  accessory is unchanged.

* `FoldInfo.display` is `none` on Android when no fold is visible. A folding
  feature is only reported for the display that has the fold, so seeing one
  means `inner`; the absence of one means closed, or on a cover display, or not
  a foldable, and Android offers no documented way to tell those apart.
* `FoldInfo.pose` is `unknown`, never `closed`, on Android. `FoldingFeature`
  has no closed state and a shut device reports no feature, so `closed` would
  have to be inferred from an absence.
* Region margins are zero on Android. The platform reports hardware bounds with
  no clearance around them, so `frame` and `reservedRect` are the same
  rectangle — unlike iOS, where the frame arrives with clearance built in.
* The capture accessory remains iOS-only. On Android its methods answer rather
  than fail, so shared code can call them unconditionally.
* The hinge angle is passed through unvalidated on Android. The sensor is not
  range-checked by the platform, and readings outside 0..180 are delivered as
  they arrive — 270 was observed reaching Dart as 270°. Clamping without
  knowing a real device's convention would hide exactly the vendor differences
  worth characterising, so the raw reading is reported. Prefer `pose` over
  `hingeAngle` for layout.
* Verified on the Android emulator only. No physical foldable hardware, on
  either platform.

## 0.1.0

First release. Fold awareness for the foldable iPhone.

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
