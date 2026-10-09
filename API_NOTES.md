# Native API reference

Every Apple symbol `bifold` calls, with its verified signature and the date it
was checked. Kept so that a change in the platform can be spotted against a
written record rather than rediscovered.

## How these were verified

Two independent passes on 2026-09-20, which agree on every symbol.

1. **Runtime introspection** on a booted iPhone Duo simulator running iOS 27.1,
   via `class_copyMethodList` and `class_copyPropertyList`. Reproducible:

   ```sh
   cd example
   flutter test integration_test/native_api_probe_test.dart -d <duo-udid>
   ```

2. **The iOS 27.1 SDK headers**, from Xcode 27.1:

   ```sh
   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
     bash scripts/verify-sdk.sh
   ```

Type encodings below are quoted verbatim. Reading them: `@` object, `:`
selector, `B` BOOL, `Q` NSUInteger, `q` NSInteger, `@?` block, `{…}` struct.

Symbols are resolved through the Objective-C runtime rather than the SDK, so
one binary builds on Xcode 26.x and 27.0 and still works on a 27.1 device. The
encodings recorded here are what make that safe: they settle whether a selector
takes objects or scalars, which decides how it can be called.

---

## Reserved regions

### `-[UIView reservedRegionsOfKind:]`

```
@24@0:8@16
```

One **object** argument, returns an object. Callable with `perform(_:with:)`.

### `-[UIView reservedRegionsOfKind:options:]`

```objc
- (nonnull NSArray<UIViewReservedRegion *> *)
    reservedRegionsOfKind:(nonnull UIViewReservedRegionKind *)kind
                  options:(UIViewReservedRegionQueryOptions)options
    API_AVAILABLE(ios(27.1), tvos(27.1), visionos(27.1));
```

Encoding `@32@0:8@16Q24` — an object, then an **`NSUInteger` scalar**.

`perform(_:with:with:)` cannot call this: it boxes both arguments as objects,
so it would pass an `NSNumber` pointer where a machine word is expected.
`FoldReader.regionsWithOptions` casts `objc_msgSend` to the exact signature.

### `UIViewReservedRegionKind`

A class, not a string typedef. Its values come from class methods:

```objc
+ (instancetype)divisionRegionKind;   // @16@0:8
+ (instancetype)occlusionRegionKind;  // @16@0:8
```

There are no exported `UIViewReservedRegionKind*` constants — `dlsym` finds
none — so these class methods are the only way to obtain a kind, and the
selector cannot be called without one.

### `UIViewReservedRegion`

```objc
/// A region within a view's coordinate space that has been reserved by
/// another entity.
@property (nonatomic, readonly) UIViewReservedRegionIdentifier *identifier;
@property (nonatomic, readonly) UIViewReservedRegionKind *kind;
/// The rect of the region in the view's coordinate space, including the margins.
@property (nonatomic, readonly) CGRect frame;
/// The margins included in the frame around the reserved rect for interactive content.
@property (nonatomic, readonly) UIEdgeInsets margins;
@property (nonatomic, readonly, getter=isActive) BOOL active;
```

Two things here shape the Dart model:

**Coordinates are the receiving view's own space**, in points. A UIKit point
and a Flutter logical pixel are the same unit, so nothing is scaled crossing
the channel.

**`frame` already contains `margins`.** The frame is the whole area to avoid;
the margins say how much of it is clearance rather than hardware. `bifold`
exposes `FoldRegion.frame` as reported and `FoldRegion.reservedRect` as
`margins.deflateRect(frame)`. Nothing inflates the frame anywhere.

`frame` and `margins` are structs, so KVC returns them boxed in `NSValue`.
Casting a boxed value straight to `CGRect` fails silently and drops every
region; both are unboxed with `.cgRectValue` / `.uiEdgeInsetsValue`.

### `UIViewReservedRegionQueryOptions`

```objc
typedef NS_OPTIONS(NSUInteger, UIViewReservedRegionQueryOptions) {
    UIViewReservedRegionQueryOptionsNone = 0,
    UIViewReservedRegionQueryOptionsIncludeInactive = 1 << 0
};
```

Without `IncludeInactive` the query returns only active regions, and most
regions are inactive until their hardware is in use.

---

## Hinge

### `UIHingeInteraction`

```objc
- (instancetype)initWithUpdateHandler:
    (void(^)(UIHingeInteraction *, UIHingeInteractionUpdate *))updateHandler
    NS_DESIGNATED_INITIALIZER;              // @24@0:8@?16
@property (nonatomic, getter=isEnabled) BOOL enabled;
```

`init` and `new` are `NS_UNAVAILABLE`, so the update handler is the only way to
construct one. `HingeReader.makeInteraction` allocates through `objc_msgSend`
and takes the result as retained exactly once: `alloc` returns +1 and
`initWithUpdateHandler:` consumes and returns it.

The handler "is invoked with the initial hinge state, and again whenever there
is an update", so the first value arrives shortly after the interaction is
added rather than synchronously.

### `UIHingeInteractionUpdate`

```objc
/// The current hinge state for the interaction, or `nil` when the interaction
/// leaves a hierarchy that provides hinge updates.
@property (nonatomic, readonly, copy, nullable) UIHinge *hinge;
```

That nullability is load-bearing. A non-nil hinge is the authoritative signal
that the device really folds, which is what `FoldReader.isFoldableDevice` uses.

### `UIHinge` and `UIHingeStatus`

```objc
typedef NS_ENUM(NSInteger, UIHingeStatus) {
    UIHingeStatusUnknown = 0,
    UIHingeStatusClosed = 1,
    UIHingeStatusPartiallyOpen = 2,
    UIHingeStatusFullyOpen = 3,
};

@property (nonatomic, readonly) UIHingeStatus status;
@property (nonatomic, readonly) CGFloat angle;  // radians
```

**The enum starts at `Unknown = 0`, so `Closed` is 1.** An enum has no class to
reflect on, so only the header settles this; a zero-based reading would report
every pose shifted by one.

Status and angle live on `UIHinge`, not on the interaction — the interaction
has no `status`, `hingeStatus` or `angle` member. Reading one by key would
raise `NSUnknownKeyException`, which aborts the process rather than returning
nil, so nothing here reads a key that has not been verified to exist.

Apple's guidance on the angle: "The rate and granularity of angle updates are
system policy and can change… If you only need to know whether the hinge is
closed, partially open, or fully open, prefer `status` over the angle."
`FoldInfo.pose` comes from `status`; `FoldInfo.hingeAngle` is offered
separately.

---

## Traits

### `UITraitCollection.verticalBarEdge`

```objc
typedef NS_ENUM(NSInteger, UIVerticalBarEdge) {
    UIVerticalBarEdgeUnspecified = 0,
    UIVerticalBarEdgeLeading,
    UIVerticalBarEdgeTrailing,
};

@property (nonatomic, readonly) UIVerticalBarEdge verticalBarEdge;
```

Reflects the system's preferred edge whether or not a bar is visible, and is
`Unspecified` wherever the system never places one — which is what makes it
degrade cleanly off this device.

### `UIWindowScene.screen`

Pre-existing (iOS 13+). Apple deprecated `UIScreen.main` for dual-display
devices; the scene's screen is the supported access path. No availability gate
needed.

---

## Scene accessories

### `UISceneAccessory`

```objc
+ (instancetype)cameraCaptureSceneAccessoryWithConfiguration:
    (UISceneConfiguration *)sceneConfiguration API_AVAILABLE(ios(27.1));
+ (instancetype)externalNonInteractiveSceneAccessoryWithConfiguration:
    (UISceneConfiguration *)sceneConfiguration API_AVAILABLE(ios(27.0));
```

These are **UIKit**, reachable from Objective-C. SwiftUI's
`CameraCaptureAccessory` wraps the same machinery.

Apple's framing, from the header: "The app declares what content to provide;
the system decides when and where to present it. Scene accessories enhance the
app's experience when available, but the app must remain fully functional
without them."

### `UIViewController` registration

```objc
- (UISceneAccessoryRegistration *)registerSceneAccessory:(UISceneAccessory *)accessory
    API_AVAILABLE(ios(27.0));
- (void)unregisterSceneAccessory:(UISceneAccessoryRegistration *)registration;
```

### `UISceneAccessoryRegistration`

```objc
@property (nonatomic, readonly, getter=isAvailable) BOOL available;
@property (nonatomic, readwrite, getter=isEnabled) BOOL enabled;
```

`available` is the system saying it can present; `enabled` is the app saying it
would like that. The header notes `available` "is observable during the
`updateProperties` and `layoutSubviews` lifecycle events" — UIKit's observation
tracking, not classic KVO, so there is no key path to subscribe to from a
runtime-resolved property. `bifold` refreshes it from `layoutSubviews`, which
is one of the two events Apple names.

### `UIWindowSceneSessionRoleCameraCaptureAccessory`

```objc
UIKIT_EXTERN UISceneSessionRole const UIWindowSceneSessionRoleCameraCaptureAccessory
    API_AVAILABLE(ios(27.1), tvos(27.1), visionos(27.1));
```

The system assigns this role to scenes it creates from a camera capture
accessory registration.

---

## Flutter

### `FlutterPluginRegistrar.viewController`

```objc
@property (nullable, readonly) UIViewController* viewController;
```

`Flutter.framework/Headers/FlutterPlugin.h`, documented as "the
`UIViewController` whose view is displaying Flutter content". Its `view` is the
view reserved regions are read from.

### `FlutterEngineGroup`

```objc
- (FlutterEngine*)makeEngineWithEntrypoint:(nullable NSString*)entrypoint
                                libraryURI:(nullable NSString*)libraryURI;
```

How the capture accessory's scene gets its own Flutter UI without disturbing
the app's main engine.

---

## Availability

`iPhoneOS27.1.sdk/usr/include/AvailabilityVersions.h`:

```c
#define __IPHONE_27_0   270000
#define __IPHONE_27_1   270100
```

Recorded for reference. `bifold` does not gate on it: symbols are resolved at
runtime, so the package compiles against older SDKs and still works at 27.1.

---

# Android

Every Android symbol `bifold` calls, verified 2026-09-21 by inspecting the
artifacts themselves rather than documentation: `javap` over the classes in
`window-1.2.0.aar` and `window-java-1.2.0.aar` from the local Gradle cache,
and over `android.jar` for API 36. Behaviour was then checked on a
`pixel_9_pro_fold` AVD running the `android-37.2` system image.

## Dependency

```
androidx.window:window:1.2.0
androidx.window:window-java:1.2.0
```

Pinned deliberately. Flutter 3.44.4's own Android embedding already declares
`androidx.window:window-java:1.2.0` — read from
`flutter_embedding_debug-1.0.0-39c38b759eba9bcf048f203176845d7b1baef159.pom`
in the Gradle cache — so matching it keeps the plugin from dragging an app
into a version conflict with the engine. Raising either version means
repeating that check.

## `androidx.window.layout.FoldingFeature`

```java
public interface FoldingFeature extends DisplayFeature {
  boolean isSeparating();
  FoldingFeature$OcclusionType getOcclusionType();   // NONE | FULL
  FoldingFeature$Orientation getOrientation();       // VERTICAL | HORIZONTAL
  FoldingFeature$State getState();                   // FLAT | HALF_OPENED
}
// from DisplayFeature:
public android.graphics.Rect getBounds();
```

**`State` has exactly two values: `FLAT` and `HALF_OPENED`.** There is no
closed state, and a shut device reports no folding feature at all. This is the
single most important fact about the Android side: the absence of a feature
cannot be distinguished from a non-foldable device by observation alone, which
is why `pose` reports `unknown` rather than `closed` when nothing is there.

It also confirms that `FoldPose` needs no new cases: `FLAT` and `HALF_OPENED`
map onto `fullyOpen` and `partiallyOpen`, which iOS already reports.

`bounds` is in **pixels**, relative to the window. Divided by
`resources.displayMetrics.density` to reach the logical pixels Dart uses.

## `androidx.window.java.layout.WindowInfoTrackerCallbackAdapter`

```java
public final void addWindowLayoutInfoListener(
    android.app.Activity, java.util.concurrent.Executor,
    androidx.core.util.Consumer<WindowLayoutInfo>);
public final void removeWindowLayoutInfoListener(
    androidx.core.util.Consumer<WindowLayoutInfo>);
```

Used in preference to `WindowInfoTracker.windowLayoutInfo()`, which returns a
`kotlinx.coroutines.flow.Flow` and would put a coroutines dependency in the
plugin for no gain.

## `androidx.window.layout.WindowMetricsCalculator`

```java
public static WindowMetricsCalculator getOrCreate();
public abstract WindowMetrics computeCurrentWindowMetrics(android.app.Activity);
// WindowMetrics:
public final android.graphics.Rect getBounds();
```

The source for size classes, which Android does not report the way UIKit does.
Read on every payload, never cached: folding, unfolding and multi-window all
resize the window without necessarily producing a new activity.

## `android.hardware.Sensor`

```java
public static final int TYPE_HINGE_ANGLE = 36;
public static final String STRING_TYPE_HINGE_ANGLE = "android.sensor.hinge_angle";
```

API 30 and later, guarded with `Build.VERSION.SDK_INT >= R`.

**Reports degrees.** Confirmed on the emulator, which registers the sensor as
`Goldfish hinge sensor0 (in degrees) | type: android.sensor.hinge_angle(36)`.
`HingeReader` converts to radians with `Math.toRadians` so the channel carries
the units `FoldInfo.hingeAngle` documents.

## `android.content.pm.PackageManager`

```java
public static final String FEATURE_SENSOR_HINGE_ANGLE =
    "android.hardware.sensor.hinge_angle";
```

The authoritative static signal for "this device has a hinge". It answers on a
**closed** device, where no folding feature exists — the one case no runtime
observation covers. Verified present on the `pixel_9_pro_fold` AVD via
`pm list features`, and verified to keep `isFoldable` true with the device
shut.

Sufficient, not necessary: a foldable with no hinge angle sensor would report
false here and still be caught by having seen a folding feature earlier in the
process.

## Arrangements

The riskiest iOS surface in this package, and until 1.0.0 the only one with no
entry here — which was a ground-rule-2 violation, not an oversight worth
leaving. `ArrangementOracle` uses these to ask UIKit where *it* would place two
panes, and it does so by adding a child view controller to the host, so a wrong
assumption here changes the app's own view hierarchy rather than just returning
a bad number.

Verified 2026-10-09 by Objective-C runtime introspection against the iOS 27.1
SDK, cross-read with the header quotes recorded in `ArrangementOracle.swift`.
Type encodings are the real ones reported by the runtime.

### `UIArrangementViewController`

```objc
// UIArrangementViewController.h
- (void)setViewController:(UIViewController *)viewController
             forPlacement:(UIArrangementViewControllerViewPlacement)placement;  // v32@0:8@16q24
- (nullable UIArrangementViewState *)stateForPlacement:(UIArrangementViewControllerViewPlacement)placement;  // @24@0:8q16
- (void)updateArrangement:(UIArrangement *)arrangement;
```

iOS 27.1. Resolved by `NSClassFromString("UIArrangementViewController")` and
`instancesRespond(to:)` before any call, so an OS without it degrades to
`BifoldArrangement.measure` returning null rather than failing.

`stateForPlacement:` returns an autoreleased object and is called through
`objc_msgSend` typed to return `AnyObject?` rather than
`Unmanaged<AnyObject>?`. That is correct — Swift treats a `@convention(c)`
function returning a class type as +0 and inserts the retain — but it is the
opposite convention from `HingeReader.makeInteraction`, which uses `Unmanaged`
because it owns an `alloc`/`init` pair. Both sites carry a comment saying
which rule applies, because "fixing" one to match the other would introduce a
double release.

### `UIArrangementViewControllerViewPlacement`

```objc
typedef NS_ENUM(NSInteger, UIArrangementViewControllerViewPlacement) {
    UIArrangementViewControllerViewPlacementPrimary = 0,
    UIArrangementViewControllerViewPlacementSecondary = 1,
};
```

iOS 27.1. Plain `NSInteger` values, passed as the scalar argument that makes
`perform(_:with:)` unusable and `objc_msgSend` necessary.

### `UISplitArrangement`

```objc
+ (instancetype)splitArrangement;
- (void)setAxes:(UIAxis)axes;  // v24@0:8Q16
```

iOS 27.1. **UNVERIFIED as a header symbol.** Found by runtime introspection
only: `NSClassFromString("UISplitArrangement")` resolves and both selectors
respond on a booted iPhone Duo simulator running iOS 27.1, but no public
header declaring it was located, and it has no documentation page on
developer.apple.com. `ArrangementOracle.swift` marks it `(runtime)` for this
reason. It is the single most likely symbol in the package to be renamed
before iOS 27.1 reaches general availability, and because resolution is by
name at runtime, a rename makes `BifoldArrangement.measure` return null
silently. `Bifold.diagnosticReport()` now states explicitly when an expected
fold symbol fails to resolve on iOS 27.1 or later, which is the mitigation.

### `UIAxis`

```objc
typedef NS_OPTIONS(NSUInteger, UIAxis) {
    UIAxisNeither = 0,
    UIAxisHorizontal = 1 << 0,
    UIAxisVertical = 1 << 1,
    UIAxisBoth = UIAxisHorizontal | UIAxisVertical,
};
```

iOS 13.4 onwards for the type itself; used here with 27.1 arrangements. An
`NSUInteger` option set, hence the `Q` in `setAxes:`'s encoding.

### `UIArrangementViewState`

```objc
@property (readonly) CGRect frame;
@property (readonly, getter=isHidden) BOOL hidden;
```

iOS 27.1. Read by KVC through verified property names, like every other KVC
read in this package. A pane reported hidden is how UIKit says its own
arrangement has collapsed to one pane, which is what
`ArrangementMeasurement.isSplit` reports.

### `UIDevice.userInterfaceIdiom` as a fold signal

```objc
@property (nonatomic, readonly) UIUserInterfaceIdiom userInterfaceIdiom;
```

Long-standing public API, used here only to *exclude* iPad from fold claims.

**It is no longer used as positive evidence.** Until 1.0.0, `FoldReader`
fell back to `userInterfaceIdiom == .phone` when no hinge had yet been
observed, which made every iPhone on a release carrying the fold APIs report
`isFoldable: true` — and, because `readDisplay` returns `outer` for any
non-regular trait collection, `pose: closed` in portrait on an ordinary phone.
The idiom says nothing about whether a device folds, so fold evidence now
comes only from an observed hinge or an observed division region.

## Observed emulator behaviour

On `pixel_9_pro_fold`, `android-37.2`, inner display 2076x2152 at 390dpi and
cover display 1080x2424 at 390dpi:

| Device state | `isFoldable` | `pose` | `display` | regions | size classes |
|---|---|---|---|---|---|
| OPENED | true | `fullyOpen` | `inner` | 1, inactive | regular/regular |
| HALF_OPENED | true | `partiallyOpen` | `inner` | 1, **active** | regular/regular |
| CLOSED (cover) | true | `unknown` | `none` | 0 | compact/regular |

On the flip-style AVD (generic `6.7in Foldable`), half-open at 90 degrees:
`formFactor` `flip`, `pose` `partiallyOpen`, one active region, and
`foldOcclusion` **supported** — the one capability the book-style device never
produces. Its device states are `CLOSED`, `HALF_OPENED` and `OPENED` only,
with no `REAR_DISPLAY_MODE`, so `rearDisplay` stays `unknown` there rather
than being claimed.

`adb shell cmd device_state state <n>` changes posture; the hinge angle is a
separate channel, injected with `adb emu sensor set hinge-angle0 <degrees>`.
Forcing a device state does **not** move the sensor, so the two must be set
together to model a real fold.

The emulator's own fold control exposes only the three device states, hence
only 0°, 90° and 180°. The sensor itself is continuous: values of 7, 23, 61,
113, 137 and 166 were injected and read back exactly, as were fractional
values (0.25, 45.5, 179.75).

**The sensor is not range-checked, and out-of-range readings are delivered.**
Setting 270 was observed arriving at Dart as 270°, with the platform's own
device-state logic independently reporting `fullyOpen`. Negative values and 360
are accepted as well. `HingeReader` converts whatever arrives and does not
clamp: a clamp chosen without a real device's convention in hand would hide the
vendor differences the brief expects a quirks table to be built from. This is
the strongest argument so far for that table being needed.

The AVD also advertises `REAR_DISPLAY_MODE` and `CONCURRENT_INNER_DEFAULT`
device states, which is the first evidence that Android rear-display work is
testable here without hardware. Not yet exercised.

## `androidx.window.area` — rear display

```java
// WindowAreaController
void presentContentOnWindowArea(Binder, Activity, Executor,
                                WindowAreaPresentationSessionCallback);
void transferActivityToWindowArea(Binder, Activity, Executor,
                                  WindowAreaSessionCallback);
// WindowAreaSessionPresenter
Context getContext();
void setContentView(android.view.View);   // a plain View
// WindowAreaCapability.Status
WINDOW_AREA_STATUS_UNSUPPORTED | _UNAVAILABLE | _AVAILABLE | _ACTIVE
```

`setContentView` taking a plain `View` is what makes presenting possible from
Flutter without managing a `Presentation`: a second engine from
`FlutterEngineGroup.createAndRunEngine`, a `FlutterView` attached to it, handed
straight to the presenter. Verified end to end on `pixel_9_pro_fold`, where
`present()` moved presentation from `available` to `active` with real Flutter
content rendering.

**Ending a session does not work on the emulator.** `WindowAreaSession.close()`
produces no `onSessionEnded` callback and `WindowAreaInfo` keeps reporting
`WINDOW_AREA_STATUS_ACTIVE` indefinitely, observed over six seconds of polling.
The second engine is destroyed correctly so nothing leaks, but the reported
status stays `active`. `bifold` passes that through rather than substituting a
value the platform is not reporting. Unverified on hardware.

## Android embedding and coordinate spaces

Verified 2026-10-09 against `window-1.2.0-sources.jar`,
`window-java-1.2.0-sources.jar` and `android.jar` (API 36) from the local
Gradle cache, rather than from documentation.

### `FoldingFeature.bounds` is window-relative

Dart documents `FoldRegion.frame` as logical pixels relative to the Flutter
**view**, and iOS delivers exactly that. `FoldingFeature.bounds` is relative
to the **window**. The two coincide whenever one Flutter view fills the
activity's content area, which is the ordinary case, and diverge otherwise.

`FoldReader.contentOffsetInWindow()` translates by the location of
`android.R.id.content` in the window, which makes the common case correct.

**UNVERIFIED:** a Flutter view that does not fill the content area — an
embedded `FlutterFragment` beside other views, or a partial-screen
multi-window layout — needs the view's own offset, and this plugin holds no
reference to the `FlutterView`. The offset measured zero in every
configuration exercised on the `pixel_9_pro_fold` and flip-style emulators,
including split-screen, so a non-zero value has never actually been observed.
The code carries a `// UNVERIFIED` marker at that method.

### The presented engine's view of fold state

`FlutterEngineGroup.createAndRunEngine(Context, DartEntrypoint)` registers
plugins by default, so a rear-display presentation's engine carries its own
`BifoldPlugin`. There is no `ActivityPluginBinding` for an engine hosted
outside an activity, so that instance never receives
`onAttachedToActivity`.

What it **can** report: `isFoldable` and a live hinge angle. Both come from
readers built in `onAttachedToEngine` from the application context, and
`Sensor.TYPE_HINGE_ANGLE` is read through a `SensorManager`, which needs a
`Context` and not an `Activity`. This is what a hinge-reactive UI on the outer
display needs, and it did not work while those readers were activity-scoped.

What it **cannot** report: `pose` and reserved regions. Those come from
`WindowInfoTracker`, whose listener is registered against an activity
(`WindowInfoTrackerCallbackAdapter.addWindowLayoutInfoListener(Activity,
Executor, Consumer)`), and a presentation's display has no activity. The
payload reports `pose: unknown` and no regions there, which is the honest
answer rather than a guess.

### `FlutterEngine.lifecycleChannel.appIsResumed()`

`FlutterActivityAndFragmentDelegate` calls this on resume, and nothing calls
it for an engine hosted outside an activity. `RearDisplay` now calls it after
attaching the `FlutterView`; without it the framework's `AppLifecycleState`
stays at whatever the engine defaulted to.

### `@ExperimentalWindowApi`

Every `androidx.window.area` symbol carries it
(`androidx/window/core/ExperimentalWindowApi.kt`), at
`RequiresOptIn.Level.WARNING`. That level is why the whole rear-display
feature compiled without anything in the source acknowledging it rests on an
experimental API. `RearDisplay`, `CapabilityReader` and `BifoldPlugin` now
carry an explicit `@OptIn(ExperimentalWindowApi::class)`.

### `EmptyWindowAreaControllerImpl`

When the window extensions are absent, `WindowAreaController.getOrCreate()`
returns this implementation, whose `windowAreaInfos` emits exactly one empty
list (`EmptyWindowAreaControllerImpl.kt:32-33`), and whose session callbacks
invoke `onSessionEnded(IllegalStateException)` **synchronously on the calling
thread** rather than through the supplied executor
(`EmptyWindowAreaControllerImpl.kt:44-52`).

The first fact is why an empty list *after* a report is treated as an
authoritative `unsupported` rather than as "not yet reported". The second is
why `releasePresentation()` must be safe to run re-entrantly inside
`present()`.

### UNVERIFIED

* `FoldingFeature.bounds` is documented as window-relative and is treated as
  such. On a Flutter activity that does not fill the window — multi-window, or
  a non-full-screen embedding — the conversion to view coordinates has not been
  checked.
* ~~`OcclusionType.FULL` never observed.~~ **Resolved 2026-09-21**: a
  flip-style AVD (generic `6.7in Foldable`) half-open reports
  `OcclusionType.FULL`, so `hasFoldOcclusion` reaches `supported` there. The
  book-style `pixel_9_pro_fold` does not, which matches the hardware: a
  book-style crease is continuous, a flip-style one can hide content.
* Nothing here has run on physical Android hardware.
