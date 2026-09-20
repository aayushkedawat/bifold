# Manual test checklist

What cannot be checked by `flutter test`. Everything here needs the iPhone Duo
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
| 1 | shut: `display: outer`, `pose: closed`, 0 regions | ✅ 2026-09-20 — verified by `integration_test/duo_fold_test.dart` |
| 2–13 | everything below | ⬜️ not yet run — needs DeviceHub fold controls |

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
