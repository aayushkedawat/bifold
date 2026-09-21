# Manual test checklist

What cannot be checked by `flutter test`.

This file has two halves. Everything up to "Android" needs the iPhone Duo
simulator in **DeviceHub** (`Xcode.app/Contents/Applications/DeviceHub.app`),
which is where the open / close / rotate / fold controls live — `simctl` has no
fold command, so none of this can be scripted.

Record the date, the Xcode version and the runtime build with each pass.

## Setup

```sh
xcrun simctl create "iPhone Duo" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-Duo \
  com.apple.CoreSimulator.SimRuntime.iOS-27-1
xcrun simctl boot <udid>
open /Applications/Xcode.app/Contents/Applications/DeviceHub.app

cd example
flutter run -d <udid>
```

Turn the debug overlay on with the toolbar button. Every check below is done
with it visible.

## Status

| # | check | result |
|---|---|---|
| 1 | shut: `display: outer`, `pose: closed`, 0 regions | ✅ 2026-09-20 |
| 2 | shut: outer display reports `compact/regular` | ✅ 2026-09-20 |
| 3 | open: `display: inner`, `pose: partiallyOpen`, live angle | ✅ 2026-09-20 — 127.8° |
| 4 | open: inner display reports `regular/regular` | ✅ 2026-09-20 |
| 5 | `BifoldScaffold` bar when compact, rail when regular | ✅ 2026-09-20 — both seen on device |
| 6 | capture accessory registers | ✅ 2026-09-20 |
| 7 | split arrangement is fold-aware | ✅ 2026-09-20 — see below |
| — | **reserved regions** | ⚠️ **never observed** — see below |

### Reserved regions are not emitted by the simulator

Checked shut and open, at 0° and at 127.8°, for both kinds, with and without
`IncludeInactive`, and across the whole view hierarchy — the Flutter view, each
ancestor, the window, and the root view controller's view. Every query returns
an empty array rather than an error, using a kind object obtained from
`+[UIViewReservedRegionKind divisionRegionKind]`.

The call path is therefore exercised and correct, but **no code that parses an
actual region has ever run**. `BifoldSplit`, `BifoldGrid`, `bifoldAnchorPoint`
and the overlay's region drawing are covered only by `FoldInfoFakes`. Treat
them as unproven against real geometry until hardware exists.

### The split arrangement *is* fold-aware

Unlike reserved regions, `BifoldArrangement.measure` responds to the fold.
Measured at the inner display's real size, 871×669:

| state | axis | result |
|---|---|---|
| open, 127.8° | horizontal | **split** — primary 0–435.67, secondary 435.67–871 |
| open, 127.8° | vertical | collapsed, secondary not visible |
| shut | horizontal | collapsed, secondary not visible |
| shut | vertical | split 50/50 |

The open horizontal split lands exactly on the midpoint of the real display and
appears only while open, so this is genuine system geometry rather than a
generic halving. It is currently the only route to real, fold-derived layout
numbers on the simulator.

---

## 1. Poses

- [x] **Shut.** `display: outer`, `pose: closed`, no regions at all. The two
      pages stack. *(Verified 2026-09-20.)*
- [ ] **Open flat.** `display: inner`, `pose: fullyOpen`. A division is listed
      but drawn faint — inactive. The pages **stack**, they do not split.
- [ ] **Part-way open.** `pose: partiallyOpen`, division drawn solid. The pages
      separate, clear of the crease and its margins.
- [ ] Close it again and confirm the state returns to shut with no regions
      left over.

## 2. Coordinates — confirm the headers in practice

The coordinate space is now **verified from the 27.1 SDK headers**: regions are
in the receiving view's own space, and `frame` already includes `margins`. This
section is no longer a risk hunt, just confirmation that the implementation
matches what the header promises.

- [ ] With the device part-way open, the overlay's filled band (the crease) and
      its outline (the crease plus clearance) both sit where the physical
      hardware is. A constant offset of roughly the status-bar height would
      mean the view-space assumption is being applied to the wrong view.
- [ ] The two pages meet at the crease, not above or below it.
- [ ] Repeat with the example wrapped in extra chrome (add padding above the
      `BifoldSplit`) — the split must still align to the real crease, which is
      what `BifoldSplit`'s view-offset measurement exists for.

## 3. Timing

`CLAUDE.md` says regions arrive after the first layout pass and must never be
cached. Confirm rather than assume:

- [ ] Cold launch open: is the first frame region-free, with regions appearing
      a frame or two later?
- [ ] Fold slowly. Does the overlay track continuously, or does the division
      lag the physical crease? Record the rough lag — third parties report
      anywhere from 3–14 ms to "milliseconds to seconds".
- [ ] Fold fast, repeatedly. Nothing should be left stale.

## 4. Rotation and size classes

The inner display does not honour supported interface orientations.

- [ ] Rotate while open. Layout follows size classes and does not break.
- [ ] Does the division ever report **vertical** (full height rather than full
      width)? `BifoldSplit` handles both axes and
      `FoldInfoFakes.partiallyOpenVertical` tests it, but it is unconfirmed
      whether the device ever reports that orientation.
- [ ] Rotate while shut, on the outer display.

## 5. Occlusion / camera cutout

- [ ] With no camera running, is the occlusion region listed but inactive?
- [ ] Open the camera. Does it become active?
- [ ] `BifoldSplit` must **not** split on an occlusion — it is an area to avoid,
      not a divider.

## 6. Transitions and lifecycle

- [ ] Fold *while the app is mid-animation*. No crash, no stuck layout.
- [ ] Background the app while open, fold it, foreground it. The reported state
      matches reality.
- [ ] Split View / Slide Over, if the Duo supports them. Confirm the
      point-to-logical-pixel mapping still holds.

## 7. Degradation

- [ ] Run on a **non-foldable** iPhone simulator on iOS 27.1: `isFoldable`
      false, no regions, pages stacked, nothing thrown. *(Covered by
      `integration_test/plugin_integration_test.dart`.)*
- [ ] Run on an **iOS 26** simulator: same, and `isSupported` false.
- [ ] Run on an **iPad** simulator on iOS 27.1. The idiom check in
      `FoldReader.isFoldableDevice` should report not-foldable.

## 8. The launch recording

Definition of done in `CLAUDE.md` asks for a short vertical clip:

- [ ] Fold → debug overlay showing the regions → split layout resolving.


---

# Android

Unlike the iOS half, all of this **can** be scripted: `adb` drives both the
posture and the hinge angle. Record the emulator image and the date with each
pass.

## Setup

```sh
$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager create avd \
  -n bifold_book \
  -k "system-images;android-37.2;google_apis_playstore_ps16k;arm64-v8a" \
  -d pixel_9_pro_fold

$ANDROID_HOME/emulator/emulator -avd bifold_book &

cd example
flutter run -d emulator-5556
```

A flip-style device is the generic `6.7in Foldable` profile ("Horizontal
Fold-in") in place of `pixel_9_pro_fold`.

## Driving it

```sh
# Posture. 0 CLOSED, 1 HALF_OPENED, 2 OPENED.
adb -s emulator-5556 shell cmd device_state state 1
adb -s emulator-5556 shell cmd device_state print-states   # what this AVD has

# Hinge angle, in degrees.
adb -s emulator-5556 emu sensor set hinge-angle0 45
adb -s emulator-5556 emu sensor get hinge-angle0
```

**The two are independent.** Forcing a device state does not move the hinge
sensor, and moving the sensor does not necessarily change the device state. A
real fold moves both, so set both, or the angle and the pose will disagree in a
way no physical device would produce.

**The emulator UI only offers three postures**, so its fold control produces
only 0°, 90° and 180°. That is a limit of the control, not of the sensor: the
sensor takes any value, and `emu sensor set` reaches it directly. To sweep:

```sh
for v in $(seq 0 5 180); do
  adb -s emulator-5556 emu sensor set hinge-angle0 $v
  sleep 0.2
done
```

Verified 2026-09-21 that arbitrary values arrive intact, including
non-detent ones (7, 23, 61, 113, 137, 166) and fractional ones (0.25, 45.5,
179.75).

**Nothing validates the range.** Values outside 0..180 are accepted by the
emulator *and delivered to the app*: setting 270 makes `bifold` report 270°,
and the platform's own device-state logic independently decided that was
`fullyOpen`. Negative values and 360 are accepted too. `bifold` passes the
sensor reading through rather than clamping it, because clamping without
knowing a real device's convention would hide the very vendor differences a
quirks table has to be built from. Worth re-checking on hardware.

Screenshots need an explicit display, because a foldable has more than one and
`screencap` otherwise warns and picks one arbitrarily:

```sh
adb -s emulator-5556 shell dumpsys SurfaceFlinger --display-id   # list them
adb -s emulator-5556 exec-out screencap -d <display-id> -p > shot.png
```

## Checks

| # | Step | Expected |
|---|---|---|
| A1 | Open (state 2), angle 180 | `foldable`, `display: inner`, `pose: fullyOpen`, 1 region **inactive**, `regular/regular` |
| A2 | Half-open (state 1), angle 45 | `pose: partiallyOpen`, division **active**, `BifoldSplit` puts the two reader pages side by side |
| A3 | Closed (state 0), angle 0 | `foldable` **still true**, `pose: unknown`, `display: none`, 0 regions, `compact/regular` on the cover display |
| A4 | A1 → A3 → A1 | `BifoldScaffold` swaps its NavigationRail for a bottom bar and back; no stale measurements from the previous display |
| A5 | Sweep the angle (see below) | the hinge gauge tracks every value, not just the detents; the angle never sticks at a previous reading |
| A6 | Rotate while half-open | the division follows the new orientation |
| A7 | Multi-window / split screen | size classes follow the window, not the display |
| A8 | Run on a non-foldable AVD | `not foldable`, no regions, **nothing logged to the console** |
| A9 | Throughout | no exception of any kind in `flutter run` output |

A3 is the one worth repeating after any change to capability detection: it is
the case observation cannot cover, and it passes only because `isFoldable`
comes from a static device feature.

## Not covered here

* Physical Android hardware. Nothing in this package has run on any.
* `OcclusionType.FULL` — no emulator state has been found that produces it.
* Activity recreation mid-fold on a device that actually recreates it; the
  emulator does not always.
* Rear display. The AVD advertises `REAR_DISPLAY_MODE` and
  `CONCURRENT_INNER_DEFAULT` device states, so this looks testable, but no
  support exists yet.
