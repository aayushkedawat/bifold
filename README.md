# bifold

Fold awareness for Flutter apps on the foldable iPhone: where the fold is,
which display you are on, and where the hardware is in the way.

On every other device — non-foldable iPhones, older iOS, iPad, Android, web and
desktop — it reports a well-defined "no fold" state and never throws.

> **Status: pre-release, and honest about it.** Read
> [Known limitations](#known-limitations) before adopting. Nothing here has been
> verified on physical hardware, because none exists yet.

## Install

```yaml
dependencies:
  bifold: ^0.1.0
```

## Use

Wrap the app once:

```dart
void main() => runApp(const BifoldScope(child: MyApp()));
```

Then read the state anywhere below it. It rebuilds when the fold changes:

```dart
final info = Bifold.of(context);

if (info.division != null) {
  // The display is creased right now.
}
```

### Split two panes across the fold

```dart
BifoldSplit(
  start: PageView(controller: left),
  end: PageView(controller: right),
)
```

When the device is part-way open and the platform reports an active division
across the widget, the panes are placed either side of the crease, clear of its
margins. Otherwise they fall back to stacking — configurable with `fallback`
(`stack`, `sideBySide`, `startOnly`).

### See what the platform is actually reporting

```dart
MaterialApp(
  builder: (context, child) => BifoldDebugOverlay(child: child!),
  home: const MyHomePage(),
)
```

Draws every reserved region: a filled band for the frame, an outline for the
frame plus margins, solid when active and faint when not. That
active/inactive distinction is usually the answer to "why didn't my layout
react?". The overlay ignores pointer events.

### Test without a device

This is the part most fold packages leave out. `FoldInfoFakes` plus
`BifoldScope.fake` exercise a fold-aware layout on any machine — no simulator,
no iOS SDK, no channel mocking:

```dart
testWidgets('reader splits across the fold', (tester) async {
  await tester.pumpWidget(
    BifoldScope.fake(
      info: FoldInfoFakes.partiallyOpen(viewSize: const Size(800, 1000)),
      child: const MyReader(),
    ),
  );
});
```

`FoldInfoFakes.poseMatrix(size)` returns every pose — including the two that
catch real bugs: a flat display that still reports an *inactive* division, and
a crease with zero thickness.

## What `FoldInfo` tells you

| member | meaning |
|---|---|
| `isFoldable` | the device has a fold this package can report on |
| `display` | `outer`, `inner`, or `none` |
| `pose` | `closed`, `partiallyOpen`, `fullyOpen`, `unknown` |
| `regions` | every reserved region, active or not |
| `division` | the active fold, or null if the display is not creased |
| `activeRegions` | regions whose hardware is currently in use |

Regions are in logical pixels relative to the Flutter view. **Never cache
them** — they arrive after the first layout pass and change as the device
folds. Read them from the current `FoldInfo` every build.

`FoldPose` mirrors the platform's own hinge states. Postures such as "book" or
"tabletop" are deliberately absent: they are Android foldable vocabulary and
this device does not report them.

## Requirements

| | |
|---|---|
| Flutter | 3.3.0+ |
| iOS deployment target | 15.0 |
| Fold reporting | iOS 27.1+ on a foldable device |
| Xcode to build | **26.x or newer — 27.1 is not required** |

The fold symbols ship in the iOS 27.1 SDK, but this package resolves them
through the Objective-C runtime rather than calling them directly. One binary
therefore builds on an older Xcode and still reports fold state on a device
that has the APIs. That matters: Flutter's own CI runs Xcode 26.2, and a
package that needed 27.1 to compile would be uninstallable for most people
until their CI upgraded.

## What is verified, and what is not

### Verified

* Every native symbol used, checked on 2026-09-20 by Objective-C runtime
  introspection **on a booted iPhone Duo simulator running iOS 27.1**. Exact
  type encodings are in [`API_NOTES.md`](API_NOTES.md), and the probe is
  reproducible: `flutter test integration_test/native_api_probe_test.dart`.
* Reading fold state end to end on that simulator, built against the iOS 27.0
  SDK — which is the proof that the runtime-resolution approach works.
* A shut device reports the outer display and no reserved regions.
* Graceful degradation on non-foldable devices, by integration test.
* The Dart layer: 68 unit and widget tests covering the model, the codec, the
  channel, and every pose.

### Not verified

* **On physical hardware: nothing.** The device has not shipped.
* **The region coordinate space.** Frames are assumed to be in the receiving
  view's own space. Not yet observed with an *opened* device, because folding
  the simulator needs DeviceHub's GUI controls and `simctl` has no fold
  command. This is the highest-risk open item — if frames are in window space
  instead, regions render at the wrong offset.
* **Region timing.** That regions arrive after the first layout pass, and how
  far they lag the hinge, are reported by others but not yet measured here.
* **The `options` flag** that includes inactive regions. Its constants are not
  exported by name; the package passes `1` and falls back to the selector that
  returns active regions regardless.

[`docs/manual-tests.md`](docs/manual-tests.md) is the checklist for closing
these, and marks which have been done.

## Known limitations

* **iOS only.** Android foldables already get display features from Flutter
  itself, so there is nothing to add there.
* **No hinge angle.** `UIHingeInteraction` exposes no readable status or angle
  — the value only arrives through a block whose signature cannot be verified
  without the 27.1 SDK. Rather than guess, `bifold` derives pose from the
  reported regions, which are fully verified. See [`API_NOTES.md`](API_NOTES.md).
* **`MediaQuery.displayFeatures` is not populated.** Only the engine can do
  that, and [flutter/flutter#193025](https://github.com/flutter/flutter/pull/193025)
  is doing it. `bifold` exposes its own model instead and deliberately does not
  fight the engine over that field.
* **No camera capture accessory.** `CameraCaptureAccessory` is SwiftUI-only and
  invisible to Objective-C, and Flutter would need multi-scene support first.
  See [`docs/phase0.md`](docs/phase0.md) §5.
* `isFoldable` uses the phone idiom to avoid reporting an iPad on iOS 27.1 as a
  foldable. A non-foldable iPhone passes that check but reports no regions, so
  it still resolves correctly.

## Prior art

`bifold` is not the only option, and
[`docs/phase0.md`](docs/phase0.md) compares them honestly.
[`foldable`](https://pub.dev/packages/foldable) exposes hinge angle and posture
and has more momentum; [`iphone_duo_ui_pro`](https://pub.dev/packages/iphone_duo_ui_pro)
ships a wider set of adaptive widgets. `bifold`'s distinct ground is the debug
overlay, first-class test fakes, and being explicit about what has and has not
been checked.

## License

See [LICENSE](LICENSE).
