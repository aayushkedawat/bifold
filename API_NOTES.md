# API_NOTES.md

Every native Apple symbol `bifold` uses, with its exact signature, minimum OS version,
source, and the date it was verified. Required by ground rule 2 in `Claude.md`.

**Verification policy.** A row may only lose its `UNVERIFIED` marker when its signature has
been read from the **Xcode 27.1 SDK headers** or an Apple documentation page showing the
declaration. Third-party agreement — even two independent implementations agreeing — is
*corroboration, not verification*. Apple's documentation site is JavaScript-rendered and
does not yield declarations to plain fetching, so headers are the practical route.

Run `scripts/verify-sdk.sh` once Xcode 27.1 is installed and paste its output here.

**Current state:** no `bifold` code exists yet (Phase 0 only). Every row below is a
*candidate* identified during research, recorded so that nothing gets silently assumed later.

**Toolchain as of 2026-09-20:** Xcode 27.0 (27A266a), iOS 27.0 SDK. Confirmed by header grep
that the 27.0 SDK declares **none** of the Duo symbols below (0 matches for each of
`UIViewReservedRegion`, `reservedRegionsOfKind`, `UIHingeInteraction`, `UIHingeStatus`,
`UIArrangementViewController`), and `simctl` lists no Duo device type. Xcode **27.1** is
required before any row here can be promoted.

---

## Status legend

| marker | meaning |
|---|---|
| ✅ VERIFIED | signature read from SDK headers or an Apple declaration |
| 🟡 CORROBORATED | two or more independent implementations agree; still unverified |
| 🔴 UNVERIFIED | single third-party source, or author flagged it as a guess |
| 📺 APPLE-NAMED | Apple named the symbol (e.g. in a Tech Talk) but gave no signature |

---

## UIKit — reserved regions

### `UIViewReservedRegion`

| field | value |
|---|---|
| status | 📺 APPLE-NAMED — type name confirmed, no declaration seen |
| signature | *unknown* |
| min OS | iOS 27.1 |
| source | [Tech Talk 111461](https://developer.apple.com/videos/play/tech-talks/111461/) |
| verified | 2026-09-20 (name only) |

Apple states this is the UIKit counterpart to SwiftUI's `ReservedRegion`, new in iOS 27.1.
A reserved region is an area claimed by hardware inside a larger usable area, and is **not**
part of the safe area. Two kinds: **division** (the fold) and **occlusion** (e.g. the
under-display front camera, active only while that camera is in use).

Properties `bifold` needs and has **not** confirmed exist: frame, margins, kind, active flag.
The draft `FoldRegion` in `Claude.md` assumes all four. Do not write that class until the
header is read.

### `-[UIView reservedRegionsOfKind:options:]` / `UIView.reservedRegions(kind:options:)`

| field | value |
|---|---|
| status | 🟡 CORROBORATED |
| signature | `reservedRegions(kind:options:)` (Swift) / `reservedRegionsOfKind:options:` (ObjC) — **parameter and return types unknown** |
| min OS | iOS 27.1 (assumed) |
| source | [flutter/flutter#193025](https://github.com/flutter/flutter/pull/193025), [berkaycatak/foldable](https://github.com/berkaycatak/foldable) |
| verified | not verified |

Two independent implementations use this selector, which is the strongest non-Apple evidence
available. Still unverified.

**Open questions that must be answered from headers before any coordinate code is written:**

1. Are regions reported in the receiving view's coordinate space or the window's? This
   decides the conversion to Flutter logical pixels and is the most likely source of a silent
   scale-factor bug.
2. Is `.includeInactive` an option on this selector? `Claude.md` records that most regions
   are inactive by default and that `.includeInactive` reveals them, but the option type's
   name and shape are unconfirmed.
3. What is the `kind` parameter's type — an enum, an option set, or an `NSString` constant?

### `GeometryProxy.reservedRegions(kind:)` (SwiftUI)

| field | value |
|---|---|
| status | 🔴 UNVERIFIED |
| source | [sunyazhou](https://www.sunyazhou.com/en/2026/09/adapting-apps-to-iphone-duo-in-ios-27/) — author explicitly flags the selector as unconfirmed |
| verified | not verified |

Not needed by `bifold` (UIKit path only). Recorded for completeness.

---

## UIKit — hinge

### `UIHingeInteraction`

| field | value |
|---|---|
| status | 🟡 CORROBORATED |
| signature | initializer takes an update/change handler — **exact shape unknown** |
| min OS | iOS 27.1 (assumed) |
| source | [flutter/flutter#193025](https://github.com/flutter/flutter/pull/193025), [berkaycatak/foldable](https://github.com/berkaycatak/foldable) |
| verified | not verified |

A `UIInteraction` added to a view. `Claude.md` notes Apple recommends reserved regions over
hinge angle *for layout* — the hinge is still needed for posture, and PR #193025 gates
division reporting on hinge status.

### `UIHingeStatus`

| field | value |
|---|---|
| status | 🟡 CORROBORATED |
| cases | `closed`, `partiallyOpen`, `fullyOpen` |
| source | [flutter/flutter#193025](https://github.com/flutter/flutter/pull/193025), [berkaycatak/foldable](https://github.com/berkaycatak/foldable) |
| verified | not verified |

**Three cases, not five.** The draft `FoldPose { closed, book, tabletop, flat, unknown }` in
`Claude.md` does not correspond to anything Apple appears to expose — `book`/`tabletop`/`flat`
are Android/Jetpack posture vocabulary. See `docs/phase0.md` §4.

### `UIHingeContext` (`.hinge.status`, `.angle`)

| field | value |
|---|---|
| status | 🔴 UNVERIFIED |
| source | [sunyazhou](https://www.sunyazhou.com/en/2026/09/adapting-apps-to-iphone-duo-in-ios-27/) |
| verified | not verified |

`foldable` exposes a hinge angle stream in degrees (0–180), implying an angle is readable
somewhere, but the owning type is unconfirmed.

---

## UIKit — screen and scene

### `UIWindowScene.screen` / `window?.windowScene?.screen`

| field | value |
|---|---|
| status | ✅ VERIFIED (pre-existing API, not new in 27.1) |
| min OS | iOS 13.0 |
| source | [Tech Talk 111461](https://developer.apple.com/videos/play/tech-talks/111461/) |
| verified | 2026-09-20 |

Apple explicitly states `UIScreen.main` is **deprecated for dual-display devices** and that
the scene's screen is the correct dynamic access path. `bifold` must use this to distinguish
inner from outer display. No `#available` gate needed.

---

## Arrangement

### `UIArrangementViewController` / `ArrangementView`

| field | value |
|---|---|
| status | 🔴 UNVERIFIED |
| source | [sunyazhou](https://www.sunyazhou.com/en/2026/09/adapting-apps-to-iphone-duo-in-ios-27/) — "probably available in UIKit"; ObjC axis restriction "likely missing" |
| verified | not verified |

`Claude.md` records `.split` and `.overlay` styles. **Not used by `bifold`** — `BifoldSplit`
is to be modeled on the behavior, not built on the API. Recorded because
[flutter/flutter#193059](https://github.com/flutter/flutter/issues/193059) tracks it.

---

## Camera (v0.2 — recommended for removal)

### `CameraCaptureAccessory`, `.sceneAccessory()`

| field | value |
|---|---|
| status | 🔴 UNVERIFIED, and **SwiftUI-only** |
| source | [Tech Talk 111465](https://developer.apple.com/videos/play/tech-talks/111465/), [sunyazhou](https://www.sunyazhou.com/en/2026/09/adapting-apps-to-iphone-duo-in-ios-27/) |
| verified | not verified |

Not visible to Objective-C at all. See `docs/phase0.md` §5 — recommended that v0.2 be cut.

### `AVCaptureDeviceDirectionCoordinator`

| field | value |
|---|---|
| status | 🔴 UNVERIFIED — reportedly main-actor-isolated, inaccessible from ObjC |
| source | [sunyazhou](https://www.sunyazhou.com/en/2026/09/adapting-apps-to-iphone-duo-in-ios-27/) |
| verified | not verified |

### `AVCaptureDeviceDiscoverySession`

| field | value |
|---|---|
| status | ✅ VERIFIED (pre-existing AVFoundation API) |
| min OS | iOS 10.0 |
| verified | 2026-09-20 |

The virtual front camera is reachable through ordinary discovery. Needs no `bifold` support.

---

## Build-time symbols (not Apple APIs, but load-bearing)

### `__IPHONE_OS_VERSION_MAX_ALLOWED >= 270100`

| field | value |
|---|---|
| status | ✅ VERIFIED (convention confirmed; the 27.1 constant itself not yet present) |
| source | `iPhoneOS27.0.sdk/usr/include/AvailabilityVersions.h:204` |
| verified | 2026-09-20 |

The installed iOS 27.0 SDK defines `#define __IPHONE_27_0 270000`, confirming the `MMmmpp`
convention. `270100` is therefore the correct spelling for iOS 27.1, as PR #193025 uses.
`__IPHONE_27_1` itself does not exist in the 27.0 SDK — re-grep once 27.1 is installed.

`bifold` must compile and pass tests on Xcode 26.x — Flutter's own CI runs 26.2, and a
package that requires 27.1 to build is uninstallable for most users until their CI upgrades.
Two viable strategies, both already in the wild:

- **compile-time gate** (PR #193025, `iphone_duo_ui_pro`'s `DUO_SDK_27_1`) — simplest, but
  a binary built on 26.x has no fold support at all, even running on a Duo;
- **Objective-C runtime resolution** (`foldable`'s default) — one binary works everywhere,
  at the cost of stringly-typed selectors and no compiler checking.

Decide in Phase 1. The runtime path is likely correct for a published package.

---

## Simulator-vs-docs behavior log

*Empty — requires the Duo simulator. Record here any behavior that differs from documentation,
per ground rule 2.*

Two lag figures to confirm against the simulator, from third parties:

| claim | source | confirmed? |
|---|---|---|
| reserved regions lag hinge updates by 3–14 ms | `foldable` | no |
| regions lag hinge status by "milliseconds to seconds" | PR #193025 | no |
| regions arrive only after the first layout pass | `Claude.md`, both impls | no |
| folded outer display reports **no** reserved regions at all | `Claude.md` | no |
