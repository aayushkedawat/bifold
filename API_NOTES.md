# API_NOTES.md

Every native Apple symbol `bifold` uses, with its exact signature, source, and
the date verified. Required by ground rule 2 in `CLAUDE.md`.

## How these were verified

**Two independent passes, both on 2026-09-20, which agree on every symbol.**

1. **Runtime introspection** on a booted iPhone Duo simulator running iOS 27.1,
   via `class_copyMethodList` and `class_copyPropertyList`. Reproducible:

   ```sh
   cd example
   flutter test integration_test/native_api_probe_test.dart -d <duo-udid>
   ```

2. **The iOS 27.1 SDK headers**, from Xcode 27.1 beta:

   ```sh
   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
     bash scripts/verify-sdk.sh
   ```

The runtime pass came first and was what made the plugin work; the headers then
confirmed it and added the two things introspection cannot show — documentation
comments and enum *values*. One of those comments corrected a real bug: see
[margins](#margins-are-inside-the-frame-not-added-to-it).

Type encodings are quoted verbatim. Reading them: `@` object, `:` selector,
`B` BOOL, `Q` NSUInteger, `q` NSInteger, `@?` block, `{…}` struct.

## Status legend

| marker | meaning |
|---|---|
| ✅ VERIFIED | observed in the live 27.1 runtime, encoding recorded below |
| 🟡 PARTIAL | the symbol is verified, one detail about it is not |
| 🔴 UNVERIFIED | not confirmed against anything authoritative |
| ⛔️ DISPROVED | previously assumed, and the runtime says otherwise |

---

## UIKit — reserved regions

### `-[UIView reservedRegionsOfKind:]`

| field | value |
|---|---|
| status | ✅ VERIFIED |
| encoding | `@24@0:8@16` — one **object** argument, returns an object |
| verified | 2026-09-20, iOS 27.1 runtime |

Callable with `perform(_:with:)`, because its only argument is an object.

### `-[UIView reservedRegionsOfKind:options:]`

| field | value |
|---|---|
| status | ✅ VERIFIED (signature) |
| encoding | `@32@0:8@16Q24` — object, then **`NSUInteger` scalar** |
| verified | 2026-09-20, iOS 27.1 runtime |

**`perform(_:with:with:)` cannot call this.** It boxes both arguments as
objects, so it would pass an `NSNumber` pointer where a machine word is
expected. `FoldReader.regionsWithOptions` casts `objc_msgSend` to the exact
signature instead.

### `UIViewReservedRegionKind`

| field | value |
|---|---|
| status | ✅ VERIFIED — it is a **class**, not a string typedef |
| class methods | `+divisionRegionKind` → `@16@0:8`<br>`+occlusionRegionKind` → `@16@0:8` |
| verified | 2026-09-20, iOS 27.1 runtime |

The kind is an **object obtained from these class methods**. This was the piece
that unblocked everything: with no kind object the selector cannot be called at
all. Note that no `UIViewReservedRegionKind*` constants are exported by symbol —
`dlsym` finds none of `…KindDivision`, `…KindOcclusion`, `…KindFold`,
`…KindCamera` — so the class methods are the only route.

### `UIViewReservedRegion`

| field | value |
|---|---|
| status | ✅ VERIFIED |
| verified | 2026-09-20, iOS 27.1 runtime |

```
@frame      {CGRect={CGPoint=dd}{CGSize=dd}}   readonly
@margins    {UIEdgeInsets=dddd}                readonly
@active     B, getter=isActive                 readonly
@kind       @"UIViewReservedRegionKind"        readonly
@identifier @"UIViewReservedRegionIdentifier"  readonly
```

`frame` and `margins` are **structs**, so KVC returns them boxed in `NSValue`.
Casting the boxed value straight to `CGRect` fails and silently drops every
region; both must be unboxed with `.cgRectValue` / `.uiEdgeInsetsValue`.

`UIViewReservedRegionIdentifier` is also a class, but exposes no class methods,
so its values are not reachable the way kinds are. `bifold` does not use it.

### `UIViewReservedRegionQueryOptions`

| field | value |
|---|---|
| status | ✅ VERIFIED |
| source | `UIViewReservedRegion.h`, iOS 27.1 SDK |
| verified | 2026-09-20 |

```objc
typedef NS_OPTIONS(NSUInteger, UIViewReservedRegionQueryOptions) {
    UIViewReservedRegionQueryOptionsNone = 0,
    UIViewReservedRegionQueryOptionsIncludeInactive = 1 << 0
};
```

Without `IncludeInactive` the query returns only active regions, and most
regions are inactive until their hardware is in use.

### Coordinate space of a region's `frame`

| field | value |
|---|---|
| status | ✅ VERIFIED |
| source | `UIViewReservedRegion.h`, iOS 27.1 SDK |
| verified | 2026-09-20 |

> "A region within **a view's coordinate space** that has been reserved by
> another entity."
> `frame`: "The rect of the region **in the view's coordinate space**, including
> the margins."

Regions are relative to the receiving view, in points. A UIKit point and a
Flutter logical pixel are the same unit, so nothing is scaled crossing the
channel. This had been the highest-risk open item; it is now closed.

### Margins are *inside* the frame, not added to it

| field | value |
|---|---|
| status | ✅ VERIFIED — and it corrected a bug |
| source | `UIViewReservedRegion.h`, iOS 27.1 SDK |

> `frame`: "The rect of the region in the view's coordinate space, **including
> the margins**."
> `margins`: "The margins **included in the frame** around the reserved rect for
> interactive content."

The frame is already the whole area to avoid. An earlier draft exposed
`avoidanceArea` as `margins.inflateRect(frame)`, which **double-counted the
clearance** and would have pushed both panes of a `BifoldSplit` too far apart
by the margin width on each side.

The Dart API now mirrors the platform: `FoldRegion.frame` is the avoid area as
reported, and `FoldRegion.reservedRect` is `margins.deflateRect(frame)` — the
bare crease or cutout inside it. Nothing inflates the frame anywhere.

---

## UIKit — hinge

### `UIHingeInteraction`

| field | value |
|---|---|
| status | ✅ VERIFIED, and in use |
| source | `UIHingeInteraction.h`, iOS 27.1 SDK |
| verified | 2026-09-20 |

```objc
- (instancetype)initWithUpdateHandler:
    (void(^)(UIHingeInteraction *, UIHingeInteractionUpdate *))updateHandler
    NS_DESIGNATED_INITIALIZER;
@property (nonatomic, getter=isEnabled) BOOL enabled;
```

`init` and `new` are `NS_UNAVAILABLE`, so the update handler is the only way
to construct one. `bifold` allocates it through `objc_msgSend` and takes the
result as retained exactly once — `alloc` returns +1 and `initWithUpdateHandler:`
consumes and returns it. See `HingeReader.makeInteraction`.

The handler "is invoked with the initial hinge state, and again whenever there
is an update", which is why the angle shows up shortly *after* the stream is
first listened to rather than on the first reading.

### `UIHingeInteractionUpdate`

| field | value |
|---|---|
| status | ✅ VERIFIED |
| source | `UIHingeInteraction.h`, iOS 27.1 SDK |

```objc
@property (nonatomic, readonly, copy, nullable) UIHinge *hinge;
```

Documented as nil "when the interaction leaves a hierarchy that provides hinge
updates". That nullability is load-bearing: a non-nil hinge is the
authoritative "this device really folds" signal, which is what `bifold` uses
for `isFoldable` in place of a device-idiom guess.

### `UIHinge` and `UIHingeStatus`

| field | value |
|---|---|
| status | ✅ VERIFIED |
| source | `UIHinge.h`, iOS 27.1 SDK |

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

**The enum starts at `Unknown = 0`, so `Closed` is 1.** Runtime introspection
could not show this — an enum has no class to reflect on — and an earlier draft
of this package guessed a zero-based `closed/partiallyOpen/fullyOpen` ordering,
which would have reported every pose shifted by one. The regions-derived
fallback was used instead until the SDK settled it. This is the clearest case
in the project for why guessing was not allowed.

Apple's own guidance on the angle: "The rate and granularity of angle updates
are system policy and can change... If you only need to know whether the hinge
is closed, partially open, or fully open, prefer `status` over the angle."
`bifold` follows this — `FoldInfo.pose` comes from `status`, and
`FoldInfo.hingeAngle` is offered separately.

### ⛔️ There is no `status` property on the interaction

Runtime introspection showed `responds to -status`, `-hingeStatus` and `-angle`
all **false** on `UIHingeInteraction`, and the header confirms why: status and
angle live on `UIHinge`, reached through the update. An earlier draft read
`value(forKey: "status")` on the interaction, which is not merely wrong — KVC
raises `NSUnknownKeyException` for an undefined key, which **aborts the
process**. It was caught by exactly that crash.

---

## UIKit — screen, scene, arrangement

### `UIWindowScene.screen`

| field | value |
|---|---|
| status | ✅ VERIFIED (pre-existing API, iOS 13+) |
| source | [Tech Talk 111461](https://developer.apple.com/videos/play/tech-talks/111461/) |

Apple states `UIScreen.main` is deprecated for dual-display devices. No
`#available` gate needed.

### `UIArrangementViewController`

| field | value |
|---|---|
| status | ✅ VERIFIED present (not used by `bifold`) |
| methods | `-setViewController:forPlacement:` → placement is `q` (`NSInteger`)<br>`-setViewController:forPlacement:animated:`<br>`-stateForPlacement:` → object<br>`-performUpdateWithAnimated:update:` |
| verified | 2026-09-20, iOS 27.1 runtime |

`BifoldSplit` is modelled on the behaviour, not built on this API. Recorded
because [flutter/flutter#193059](https://github.com/flutter/flutter/issues/193059)
tracks it.

---

## Flutter — reaching the view

### `FlutterPluginRegistrar.viewController`

| field | value |
|---|---|
| status | ✅ VERIFIED |
| declaration | `@property(nullable, readonly) UIViewController* viewController;` |
| source | `Flutter.framework/Headers/FlutterPlugin.h:349` |
| verified | 2026-09-20 |

Documented there as "the `UIViewController` whose view is displaying Flutter
content". Its `view` is the view reserved regions are read from — the answer to
Phase 0 question 4.

⛔️ **There is no `registrar.view()`.** An earlier draft called it and the build
failed. `FlutterPluginRegistrar` has no such member.

---

## Camera (v0.2 — recommended for removal)

### `CameraCaptureAccessory`, `.sceneAccessory()`

| field | value |
|---|---|
| status | 🔴 UNVERIFIED, and SwiftUI-only |
| source | [Tech Talk 111465](https://developer.apple.com/videos/play/tech-talks/111465/) |

Invisible to Objective-C, and [flutter/flutter#193055](https://github.com/flutter/flutter/issues/193055)
notes Flutter needs multi-scene support first. See `docs/phase0.md` §5.

---

## Build-time

### `__IPHONE_OS_VERSION_MAX_ALLOWED >= 270100`

| field | value |
|---|---|
| status | ✅ VERIFIED (convention) |
| source | `iPhoneOS27.0.sdk/usr/include/AvailabilityVersions.h:204` |

`#define __IPHONE_27_0 270000` confirms the `MMmmpp` convention, so `270100` is
correct for iOS 27.1.

**`bifold` does not use this gate.** It resolves symbols through the
Objective-C runtime instead, so one binary builds on Xcode 26.x/27.0 and still
works on a 27.1 device. This is verified in both directions: the package is
built here with the 27.0 SDK and reads fold state correctly on a 27.1 runtime.

---

## Observed behaviour

| claim | source | status |
|---|---|---|
| a shut Duo reports **no** reserved regions | `CLAUDE.md` | ✅ confirmed — live read on the Duo simulator returned `display: outer, pose: closed, regions: 0` |
| regions arrive only after the first layout pass | `CLAUDE.md`, both competing impls | 🔴 not yet observed |
| regions lag hinge updates by 3–14 ms | `foldable` package | 🔴 not yet observed |
| regions lag hinge status by "ms to seconds" | flutter/flutter#193025 | 🔴 not yet observed |

These are *timing* claims, and timing cannot be read out of a header — it needs
the Duo simulator **opened** and folded, which requires DeviceHub's fold
controls. `docs/manual-tests.md` §3 has the checklist. None of them affect
correctness of the geometry, which is now fully verified.
