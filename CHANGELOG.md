## 1.0.1

Packaging and project documentation. No change to any published API, and no
change to behaviour on either platform.

**Fixed**

* **The published archive now carries an example.** `.pubignore` excluded the
  whole of `example/` — correct for a directory holding two native projects,
  but it also hid `example/README.md`, which is the first path pana looks for
  when deciding whether a package ships an example. So pub.dev scored 0/10 for
  "Package has an example" while the example app sat in the repository, fully
  built and running on both platforms. That one file is now published; the
  rest of the directory still is not.

  Note the pattern it took: `example/` with a trailing slash stops pub
  descending into the directory at all, so a negation inside it can never
  re-include anything. It has to be `example/*` followed by
  `!example/README.md`.

**Changed**

* **`example/README.md` is now an example, not the Flutter template.** It was
  the untouched "A few resources to get you started if this is your first
  Flutter project" boilerplate, which is what pub.dev would have rendered as
  the Example tab. It now covers the minimum setup, the aspect-scoped
  accessors, a two-pane layout, the capability API, and what each tab of the
  example app demonstrates.

**Added**

* **The example app demonstrates how to read fold state, not just what it
  says.** A new **Reads** tab counts the builds each accessor causes, so
  folding the device shows `Bifold.of` climbing while `Bifold.poseOf`,
  `hingeAngleOf`, `regionsOf` and `displayOf` sit still until their own aspect
  moves. The same tab drives `BifoldArrangement.measure()`, including the
  `release()` it asks for — both were documented in the README and
  demonstrated nowhere.

  The app now also *practises* this. `HingeGauge` took a whole `FoldInfo` and
  so rebuilt on every update, which for the one widget redrawn at sensor rate
  is the exact pattern the README warns against; it now takes the `radians`
  and `pose` it draws, and its caller watches those two aspects.

* **Project documentation**: `CONTRIBUTING.md`, `SECURITY.md`, and a
  Contributor Covenant 2.1 `CODE_OF_CONDUCT.md`, plus issue forms and a pull
  request template under `.github/`.

  The device report form is the one that matters. Nothing in this package has
  run on physical hardware on either platform, so it asks for the output of
  `Bifold.diagnosticReport()`, which poses were reported correctly, and what
  did not match — including the three rear-display paths that have never
  completed a round trip. `SECURITY.md` states the attack surface rather than
  implying one: no network code, no permissions, nothing persisted.

The archive grows from 152 KB to 158 KB, still well inside the 2 MB ceiling
CI enforces.

## 1.0.0

A stable API, and the correctness pass that earns the version number. Six bugs
below were each reproduced by a test before being fixed; those tests ship.

**Breaking**

* **`BifoldSplit.fallback` now defaults to `BifoldSplitFallback.adaptive`**,
  which lays the panes side by side where there is room and stacks them where
  there is not. The old default, `stack`, was wrong for the case two-pane
  layouts exist for: a fold is only reported as *active* while the device is
  part-way open, so a flat open inner display took the fallback path and got
  two panes one above the other on a tablet-sized screen. Pass
  `fallback: BifoldSplitFallback.stack` to keep the previous behaviour.
* **`FoldInfo.isResolved` is read strictly from the platform payload.** A
  payload that omits the key now reports `isResolved: false`. Both platforms
  send it. This matters because the old default of `true` meant a payload
  arriving before the platform could establish anything — the iOS view not yet
  loaded, Android before its first window-layout callback — decoded as a
  confident "there is no fold", which is the exact conflation `isResolved` was
  added to remove.
* **A platform with no native side now reports `FoldInfo.none`, not
  `FoldInfo.unsupported`.** Having no implementation is a conclusive answer, so
  it resolves. `FoldInfo.unsupported` keeps its meaning and is now only the
  pre-answer seed a `BifoldScope` holds before anything has reported. Before
  this, `FoldInfo.none` was unreachable from the real platform path, so a
  layout that gated its first frame on `isResolved` — as the field's own
  documentation recommends — waited forever on web and desktop.

**Deprecated**

* `BifoldCaptureAccessory` is deprecated in favour of `BifoldRearDisplay`,
  which covers the same behaviour on both platforms: `present()` replaces
  `register()` plus `setEnabled(true)`, `end()` replaces `unregister()`, and
  availability reports four states rather than a boolean. It keeps working and
  will be removed in 2.0.0.

**Added**

* **Aspect-scoped fold access.** `Bifold.poseOf(context)`,
  `Bifold.hingeAngleOf(context)`, `Bifold.regionsOf(context)` and
  `Bifold.displayOf(context)` each rebuild their caller only when that part of
  the state changes. `Bifold.of(context)` still depends on everything and
  remains the default. Measured before: 240 hinge updates across 30
  fold-aware widgets produced 7170 builds, because `FoldInfo` equality
  includes the hinge angle and one inherited widget carried the whole state,
  so a widget reading only `pose` rebuilt on every sensor sample.
* `Bifold.listenable`, a `ValueListenable<FoldInfo>` for code outside the
  widget tree — a controller, a bloc, an animation. One object for the
  process, one platform subscription behind it, subscribed on its first
  listener and released with its last. Previously every adopter wrote this by
  hand over `Bifold.stream`.
* **Rear display goes through `BifoldPlatform`.** `rearDisplayStatus()`,
  `rearDisplayAvailabilityStream()`, `presentOnRearDisplay()`,
  `transferToRearDisplay()` and `endRearDisplay()` are now part of the
  platform interface, so `FakeBifoldPlatform` can drive them. Testing the
  four rear-display states used to mean hand-writing `StandardMethodCodec`
  plumbing against the unexported channel name `dev.bifold/rear_display`, and
  only one case could be covered per test file because the availability
  stream was a memoised process-global.
* `BifoldScaffold.showNavigationBeforeResolved`, defaulting to false: until
  the platform has answered it renders the body with no navigation rather
  than guessing, which stops an app launching on an open foldable showing a
  bottom bar for a frame and then swapping it for a rail.
* `RearDisplayFakes` — unresolved, unsupported, unavailable, available,
  presenting and both-modes — plus `BifoldCapabilityFakes.dualScreen()` and
  `BifoldCapabilityFakes.bookWithTransfer()`, the only profile offering
  `RearDisplayMode.transfer`.
* `FakeBifoldPlatform` gained the affordances its own tests needed:
  `emitRearDisplay`, `rearDisplayRequestsSucceed`, `rearDisplayCalls`,
  `holdNextRead`/`completePendingRead` (for the seed-query-versus-stream
  race), `emitError`, `foldStreamRequests` and `foldStreamIsSubscribed`.
* `RearDisplayAvailability.unresolved`, and `isResolved` on
  `RearDisplayAvailability`. Four statuses could not express "nothing has
  reported yet": both it and "this device cannot present" read as
  `unsupported`, so a UI had to hide its control before the platform had
  spoken.
* `kBifoldRegularWidthBreakpoint`, the single documented width at which this
  package decides two panes fit when no size class has been reported. 600
  logical pixels, matching Material's compact-to-medium boundary.
* `FoldInfo.capabilityRevision`. Plumbing rather than something to read, and
  deliberately not part of `FoldInfo` equality.
* Fakes that can drive the paths the shipped ones could not reach:
  `FoldInfoFakes.flat` (a resolved non-foldable phone — the most common device
  in any install base, and a case `FoldInfo.unsupported` cannot stand in for),
  `FoldInfoFakes.silentHinge` (a sensor present but never delivering), and
  size classes on the inner-display fakes so `FoldInfo.isRegular`, and
  therefore `BifoldScaffold`'s rail, can be tested at all. Every
  `FoldInfoFakes` value now reports `isResolved: true`, because each models a
  platform answer; a consumer gating on resolution could not previously be
  driven out of its pending state by any fake the package shipped.

**Fixed**

* **A rear-display session no longer ends when the device folds.** On Android
  the session was torn down from the activity's configuration-change path, and
  folding *is* a configuration change — so the one gesture this package exists
  to report closed the presentation it was presenting. Because
  `transferActivityToWindowArea` causes a configuration change by design,
  `transferActivity()` could not previously complete at all.
* **The hinge angle no longer drops to null mid-fold on Android.** The sensor
  listener was activity-scoped, so every fold unregistered it and pushed a
  payload with `hingeAngle: null` in the middle of the gesture. It reads
  through a `SensorManager`, which needs a `Context` and not an `Activity`, so
  it is now engine-scoped and follows whether anyone is listening.
* **Android no longer reports an authoritative "no hinge sensor" on a device
  that has one.** The reader was built when an activity attached, so any
  capability query before that found it absent and reported `unsupported` with
  an authoritative source.
* **A capability can no longer regress from `unsupported` to `unknown`.** A
  later report that merely explained *why* it saw nothing replaced a settled
  negative, turning "this device has no hinge sensor" back into "nobody
  knows". Only positive evidence may now overturn a negative.
* **`hasFold` can no longer be true alongside `formFactor` of `none`.** The
  form factor latched on `none` — documented as "not a folding device" — and a
  later report proving a fold while the shape was still unknown left the two
  contradicting each other. Reachable in practice, because a missing plugin or
  a null payload absorbs `BifoldCapabilities.none` before a real device
  reports in.
* **`BifoldCapabilities.raw` is merged across reports rather than replaced.**
  It is documented as the escape hatch for reading a capability a newer native
  build added, and reports do not all carry the same keys, so overwriting
  dropped what the previous one knew.
* **`BifoldScope.fake` now honours a changed `capabilities` argument.** It
  compared only the fold state, so pumping the same `FoldInfo` with a
  different capability profile — the natural shape of a table-driven
  capability test — silently kept the old profile and the test passed while
  asserting the wrong thing.
* **Capabilities are no longer re-queried on every fold event.** The stream
  called `getCapabilities()` per event, and the fold stream carries the hinge
  angle, so a fold in progress cost one platform round trip per sensor
  sample — measured at 60 events for 60 round trips and one useful emission.
  The native side now stamps each fold payload with a `capabilityRevision` it
  bumps only on a real capability change, and Dart queries on that.
* **iOS no longer claims every iPhone is foldable.** Until the first hinge
  update the fallback was the phone idiom, so an ordinary iPhone on a release
  carrying the fold APIs reported `isFoldable: true` — and, because the display
  reading returns `outer` for any non-regular trait collection, `pose: closed`
  in portrait. It now answers from evidence, agreeing with `CapabilityReader`
  instead of guessing.
* **iOS no longer reports an error when its view has not loaded yet.**
  `getFoldInfo` returned a `FlutterError`, which Dart surfaced through
  `FlutterError.reportError`, putting a red error in the console on a healthy
  launch. It now answers with an unresolved payload, as Android does.
* **Android reports `unsupported` for rear display where the window extensions
  are absent.** An empty window-area list was treated as "not yet reported" and
  stayed `unknown` forever on every non-foldable device, when it is in fact an
  authoritative negative.
* **The Android form factor no longer flips between `book` and `flip`.** The
  hinge orientation was sticky while the rotation was read live at payload
  time, and the two only mean anything together, so an orientation observed in
  landscape combined with a later portrait rotation changed the device's shape.
* **The iOS fold stream can no longer be born dead.** If the Flutter view had
  not loaded when Dart subscribed, the plugin emitted one unsupported payload
  and returned without creating an observation and with no retry — so the
  stream stayed open and silent for the life of the engine, reporting no fold
  forever on a real foldable. It now retries attachment until the view
  appears, bounded so it cannot keep a timer alive on a device with no fold.
* **The iOS layout sentinel no longer leaks on hot restart.** Re-listening
  assigned a new observation without cancelling the old one, and
  `FoldObservation` held its sentinel weakly while the superview held it
  strongly — so the old sentinel could never be reached to remove it, stayed
  in the view hierarchy with a live layout callback, and double-emitted, one
  extra copy per restart.
* **`BifoldScaffold` no longer renders phone chrome on a wide desktop
  window.** `isRegular` depends on size classes that only a native plugin
  supplies, so at 1600x1000 with no native side it drew a `NavigationBar`. It
  now falls back to the window width against
  `kBifoldRegularWidthBreakpoint` when no size class was reported, and a
  reported size class still wins over the measured width.
* **iOS capabilities no longer claim OS facts as device facts.**
  `halfOpenedPosture`, `coverDisplay` and `reservedRegions` were keyed off the
  running iOS *declaring* the fold symbols, so a non-foldable iPhone on a
  release that has them reported `hasCoverDisplay: true` — and an iPad
  reported `fold: unsupported` beside `coverDisplay: supported`, which is not
  a state that exists. They are now gated on fold evidence, so a capability
  can never be more certain than the fold it depends on.
* **iOS no longer claims every iPhone is foldable.** Until the first hinge
  update the fallback was the phone idiom, so an ordinary iPhone reported
  `isFoldable: true` and, because the display reading returns `outer` for any
  non-regular trait collection, `pose: closed` in portrait. Fold evidence now
  comes only from an observed hinge or an observed division region.
* **Both rear-display surfaces work at the same time on iOS.**
  `CaptureAccessory.onAvailabilityChanged` is a single slot on a process-wide
  singleton, and `BifoldCaptureAccessory` and `BifoldRearDisplay` each
  assigned it directly — so whichever registered last silently deadened the
  other stream, which is the one thing deprecating rather than removing the
  accessory must not do. The plugin owns the slot now and fans out to both.
* **Rear-display availability no longer depends on a fold subscription.**
  `refreshAvailability()` was driven only by the *fold* stream's layout
  sentinel, so an app that bound `BifoldRearDisplay.availability` without also
  listening to the hinge got one value and then nothing, ever. The accessory
  has its own layout watcher now.
* **The iOS plugin tears down when its engine is destroyed.**
  `detachFromEngine(for:)` was never implemented, so the layout sentinel, the
  hinge interaction and — the live one — the arrangement oracle's child view
  controller stayed parented to a host whose engine was gone.
* **Android region bounds are translated into view coordinates.**
  `FoldingFeature.bounds` is window-relative while Dart documents, and iOS
  delivers, view-relative — so `FoldRegion.isSeparating(viewSize)`, which
  `BifoldSplit` keys off, could decide a full-width fold did not span the box.
  The remaining gap (an embedded Flutter view that does not fill the content
  area) is marked `// UNVERIFIED` and recorded in `API_NOTES.md`.
* **The Android presented engine is told it is resumed.** Nothing called
  `lifecycleChannel.appIsResumed()` for an engine hosted outside an activity,
  which can leave the presented surface never producing a frame.
* **The Android form factor no longer flips between `book` and `flip`.** The
  hinge orientation was sticky while the rotation was read live at payload
  time, and the two only mean anything together.
* The diagnostic report reads its `androidx.window` version from
  `BuildConfig` instead of a hardcoded string, which would have kept
  reporting 1.2.0 after the dependency moved — in the one string whose whole
  purpose is to be accurate in a bug report.
* `Bifold.diagnosticReport()` no longer force-unwraps a hinge angle while
  formatting `FoldInfo`.

**Packaging**

* The published archive is **112 KB**, down from 7 MB. A `.pubignore` keeps the
  README animation, the example app and the research notes out of it;
  `pub publish --dry-run` had been reporting 0 warnings while shipping a 9 MB
  screen recording, so CI now fails if the archive grows past 2 MB.
* The README's install snippet said `^0.1.0` while the package was at 0.3.0.
* The podspec carried its template metadata: version `0.0.1`, summary "A new
  Flutter plugin project.", homepage `http://example.com`.

**Hardening**

* **The diagnostic report now says when an expected fold symbol did not
  resolve.** This package resolves Apple's fold symbols by name at runtime so
  that one binary builds on an older Xcode and still runs the fold path on a
  new OS — but the cost is that a renamed or withdrawn symbol fails silently,
  reporting "no fold" forever with nothing to distinguish it from an ordinary
  phone. `UIHingeInteraction` and `UIHinge` were still flagged beta on iOS
  when this shipped, which is exactly when a rename is most likely. On iOS
  27.1 or later, a symbol that fails to resolve is now called out in the
  report as a bug in this package.
* **The native API probe can no longer crash the app it is diagnosing.** It
  invoked `reservedRegionsOfKind:options:` with no `responds(to:)` guard,
  unlike every other runtime call in the package.
* **`describeConstants()` is removed.** It used `dlsym` to look for globals
  named `UIViewReservedRegionKindDivision` and friends, which `API_NOTES.md`
  records as not existing — the kinds come from class methods instead. It
  answered a settled question, shipped in release builds, and put
  UIKit-prefixed symbol strings in the binary for an App Store scanner to
  flag.
* The dead `PrivacyInfo.xcprivacy` is removed. It was bundled by neither
  SwiftPM nor CocoaPods, which also made it an unhandled-resource build
  warning and swept it in as a source file. This plugin calls no
  required-reason API, so no manifest is required — and a dead one is worse
  than none.
* `android/build.gradle.kts` no longer carries a `buildscript` block whose
  AGP and Kotlin classpaths nothing applied. Kotlin compiles via AGP 9's
  built-in support, which is now stated in the file rather than left to be
  discovered by whoever downgrades AGP.
* The main-thread executor keeps one `Handler` and runs inline when already on
  the main thread, instead of allocating per dispatch and always costing a
  frame.
* Every `androidx.window.area` symbol is `@ExperimentalWindowApi` at
  `RequiresOptIn.Level.WARNING`, which is why the rear-display feature
  compiled with nothing acknowledging it. The opt-in is now explicit.

**Testing and CI**

* The example's tests, including the three downstream consumers that are this
  package's evidence that no app needs a `Platform.isIOS` branch, now run in
  CI. They had only ever run on a developer's machine.
* A cross-language contract test reads `BifoldPlugin.swift` and
  `BifoldPlugin.kt` and asserts that the channel names, the method names Dart
  invokes and the payload keys Dart reads strictly all appear on both sides.
  Nothing could previously catch a native rename: the test that claimed to
  asserted that a constant equalled its own literal.
* The example app finally demonstrates `BifoldRearDisplay`, with a
  `rearDisplayMain` entrypoint wrapped in its own `BifoldScope` — a second
  engine is a separate isolate and does not inherit the scope from `main`, so
  without one, content on the rear display could not react to the hinge.
* **The iOS native side is tested for the first time.** The only Swift test in
  the repo was the untouched Flutter template: it called `getPlatformVersion`,
  which this plugin does not implement, and force-cast the resulting
  `FlutterMethodNotImplemented` to `String` — so it would have crashed the
  moment anything ran it, and nothing ever did. It is replaced with six tests
  that run against the real plugin on a simulator and now run in CI. One of
  them asserts that no capability claims support while the fold itself is
  unestablished, which a non-foldable simulator is exactly the right device to
  prove.
* **The Android capability rules are unit-tested.** `CapabilityReader` needs a
  `Context` and so could not be built in a JVM test, which is why none of this
  was covered. The sticky observations and the revision rule are extracted
  into `CapabilityObservations`, following the pattern `FormFactors` already
  set, and tested without adding Robolectric: 13 Kotlin tests now, up from 6.
  They pin the rule the revision exists for — that 60 identical observations
  during a fold must not bump it.
* `API_NOTES.md` has an Arrangements section, which it had never had, covering
  `UIArrangementViewController`, `UISplitArrangement` (recorded as
  runtime-only, with no header located), `UIAxis` and `UIArrangementViewState`
  — the riskiest iOS surface in the package, because it mutates the host view
  hierarchy. It also records the Android window-versus-view coordinate space,
  what a presented engine can and cannot see, and the experimental-API opt-in.
* `doc/manual-tests.md` has a rear-display checklist and a result column. It
  had claimed rear display was unsupported while the 0.3.0 changelog recorded
  it as emulator-verified.

**Still not verified on physical hardware, on either platform.** The iPhone
Duo ships on 2026-10-23. Everything above was exercised on the iOS simulator
and the `pixel_9_pro_fold` and flip-style Android emulators; see the
"what is verified where" table in the README.

## 0.3.0

*Tagged and released on GitHub, but never published to pub.dev. Everything
below reached pub.dev in 1.0.0.*

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

## 0.1.1

*Tagged and released on GitHub, but never published to pub.dev. The fix below
reached pub.dev in 0.2.0.*

**Fixed**

* Subscribing to the fold stream no longer logs a `MissingPluginException` on
  every Android, web and desktop launch. `EventChannel.receiveBroadcastStream`
  reports a failed `listen` through `FlutterError.reportError` itself, so the
  stream now asks the method channel whether a native side is registered
  before it subscribes. Fold state was always correct and nothing ever threw;
  the error simply read as a broken plugin.

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
