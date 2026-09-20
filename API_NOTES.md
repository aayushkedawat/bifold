# API_NOTES.md

Every native Apple symbol `bifold` uses, with its exact signature, source, and
the date verified. Required by ground rule 2 in `CLAUDE.md`.

## How these were verified

**By Objective-C runtime introspection on a booted iPhone Duo simulator running
iOS 27.1**, on 2026-09-20, via `class_copyMethodList` and
`class_copyPropertyList`. The probe is checked in as
`ios/bifold/Sources/bifold/NativeApiProbe.swift` and is reproducible:

```sh
cd example
flutter test integration_test/native_api_probe_test.dart -d <duo-udid>
```

This is **stronger evidence than a header read**, because it reports what the
code will actually call on the OS it will actually run on. It was also the only
route available: the iOS 27.1 *runtime* is installed here but the iOS 27.1
*SDK* is not (Xcode is 27.0), and Apple's documentation pages are
JavaScript-rendered and yield no declarations to fetching.

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

### Reserved-region `options` values

| field | value |
|---|---|
| status | 🔴 UNVERIFIED |

The parameter is an `NSUInteger` option set, but no constants are exported by
name and the declaring SDK is not installed. `FoldReader` passes `1` as the
"include inactive" flag and falls back to the one-argument selector, which
returns the active regions correctly regardless. **Confirm against the 27.1 SDK
headers before relying on inactive regions.**

### Coordinate space of a region's `frame`

| field | value |
|---|---|
| status | 🔴 UNVERIFIED |

Assumed to be the receiving view's own coordinate space, in points. Not yet
observed, because the Duo simulator reports no regions while shut and folding
it requires the DeviceHub GUI. **This is the highest-risk open item**: if the
frames are actually in window or screen space, every region lands at the wrong
offset. See `docs/manual-tests.md`.

---

## UIKit — hinge

### `UIHingeInteraction`

| field | value |
|---|---|
| status | ✅ VERIFIED (shape) |
| methods | `-initWithUpdateHandler:` → `@24@0:8@?16` (takes a **block**)<br>`-init`, `-view`, `-isEnabled`, `-setEnabled:` |
| properties | `@enabled` (BOOL, getter `isEnabled`), `@view` (`UIView`) |
| verified | 2026-09-20, iOS 27.1 runtime |

### ⛔️ There is no `status` property

| probe result | |
|---|---|
| `responds to -status` | **false** |
| `responds to -hingeStatus` | **false** |
| `responds to -angle` | **false** |

An earlier draft of `FoldReader` read `value(forKey: "status")` on the
interaction. That is not merely wrong — KVC raises `NSUnknownKeyException` for
an undefined key, which **aborts the process**. It was caught by exactly that
crash while probing. Hinge state is only reachable through the block passed to
`-initWithUpdateHandler:`, whose parameter type cannot be verified without the
SDK.

`bifold` therefore does not use the hinge at all; it derives pose from the
regions, which are fully verified. See `FoldReader.derivePose`.

### `UIHingeStatus`, `UIHingeContext`

| field | value |
|---|---|
| status | ⛔️ neither is a class |

`NSClassFromString` returns nil for both, so `UIHingeStatus` is an `NS_ENUM`.
No `UIHingeStatusClosed` / `…PartiallyOpen` / `…FullyOpen` symbols are
exported. **The draft `FoldPose { closed, book, tabletop, flat, unknown }` in
`CLAUDE.md` has no basis in the runtime** — `book`/`tabletop`/`flat` are Android
posture vocabulary. `bifold` ships `closed`/`partiallyOpen`/`fullyOpen`/`unknown`.

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

Everything still marked 🔴 needs the Duo simulator **opened**, which requires
DeviceHub's fold controls. `docs/manual-tests.md` has the checklist.
