# bifold

Fold awareness for Flutter apps on the foldable iPhone: where the fold is,
which display you are on, how far the device is open, and where hardware is in
the way.

On every other device — non-foldable iPhones, older iOS, iPad, Android, web and
desktop — it reports a well-defined "no fold" state and never throws, so it is
safe to adopt in an app that ships everywhere.

## Install

```yaml
dependencies:
  bifold: ^0.1.0
```

## Quick start

Wrap the app once:

```dart
void main() => runApp(const BifoldScope(child: MyApp()));
```

Read the state anywhere below it. It rebuilds when the fold changes:

```dart
final info = Bifold.of(context);

if (info.division != null) {
  // The display is creased right now.
}
```

## What you get

| | |
|---|---|
| `FoldInfo.pose` | `closed`, `partiallyOpen`, `fullyOpen`, `unknown` — the platform's own hinge status |
| `FoldInfo.hingeAngle` | hinge angle in radians, plus `hingeAngleDegrees` |
| `FoldInfo.display` | `outer`, `inner`, `none` |
| `FoldInfo.regions` | every reserved region, with frame, margins and active state |
| `FoldInfo.division` | the active fold, or null when the display is not creased |
| `FoldInfo.horizontalSizeClass` | `compact` / `regular`, plus `verticalSizeClass` and `isRegular` |
| `FoldInfo.verticalBarEdge` | which edge the system prefers for its vertical bar |

### Split two panes across the fold

```dart
BifoldSplit(
  start: PageView(controller: left),
  end: PageView(controller: right),
)
```

Places the panes either side of the crease, clear of its margins. With no
active division it falls back to stacking — configurable with `fallback`
(`stack`, `sideBySide`, `startOnly`).

### A grid that never bends a tile

```dart
BifoldGrid(
  tileExtent: 160,
  children: photos.map(PhotoTile.new).toList(),
)
```

Tiles fill the space before the crease, then resume after it. No tile is ever
drawn across the fold. Behaves as an ordinary wrapping grid when there is
nothing to avoid.

### Keep dialogs off the crease

```dart
showDialog(
  context: context,
  anchorPoint: bifoldAnchorPoint(context),
  builder: (context) => const AlertDialog(title: Text('Hello')),
);
```

Places the dialog in whichever half has more room. Returns null when there is
nothing to avoid, so it is safe to pass unconditionally.

### Content on the outer display while filming

With the device open and a capture session running, the system can show your
content on the outer display, facing the person being filmed — for a framing
preview, or a teleprompter.

```dart
@pragma('vm:entry-point')
void captureAccessoryMain() => runApp(const SubjectView());

// once the camera UI is up:
await BifoldCaptureAccessory.register(entrypoint: 'captureAccessoryMain');
await BifoldCaptureAccessory.setEnabled(true);
```

The accessory runs in its own Flutter engine, so your main UI on the inner
display is untouched. The system decides whether and when it appears; watch
`BifoldCaptureAccessory.availability` to follow along.

### Match the system's own split exactly

`BifoldSplit` positions panes from the reported fold. When a layout needs to
match the platform's own split arrangement rather than approximate it, ask the
platform directly:

```dart
final measured = await BifoldArrangement.measure(
  size: const Size(871, 669),
  axis: ArrangementAxis.vertical,
);
if (measured != null && measured.isSplit) {
  // Mirror measured.primary.bounds and measured.secondary.bounds.
}
await BifoldArrangement.release();
```

The numbers come from a real arrangement the platform laid out, not from a
model of one. Measuring attaches an empty, non-interactive view controller for
the duration — call `release()` when finished.

### Bridge to `MediaQuery.displayFeatures`

Flutter populates `displayFeatures` only on Android, so packages built for
Android foldables — and Flutter's own dialog positioning — see nothing on iOS.
Opt in and they work:

```dart
MaterialApp(
  builder: (context, child) => BifoldDisplayFeatures(child: child!),
  home: const MyHomePage(),
)
```

The mapping matches
[flutter/flutter#193025](https://github.com/flutter/flutter/pull/193025), and
the widget steps aside automatically once the engine populates the field
natively, so it will not fight a future Flutter release.

### See what the platform is reporting

```dart
MaterialApp(
  builder: (context, child) => BifoldDebugOverlay(child: child!),
  home: const MyHomePage(),
)
```

Draws every reserved region: a filled band for the hardware, an outline for the
hardware plus its clearance, solid when active and faint when not. That
active/inactive distinction is usually the answer to "why didn't my layout
react?". Ignores pointer events.

### Test it without a device

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

No simulator, no iOS SDK, no channel mocking. `FoldInfoFakes.poseMatrix(size)`
returns every pose for table-driven tests, including the two that catch real
bugs: a flat display that still reports an *inactive* division, and a crease
with zero thickness.

## Requirements

| | |
|---|---|
| Flutter | 3.3.0+ |
| iOS deployment target | 15.0 |
| Fold reporting | iOS 27.1+ on a foldable device |
| Xcode to build | **26.x or newer — 27.1 is not required** |

The fold symbols ship in the iOS 27.1 SDK, but `bifold` resolves them through
the Objective-C runtime rather than calling them directly. One binary builds on
an older Xcode and still reports fold state on a device that has the APIs. That
matters in practice: Flutter's own CI runs Xcode 26.2, and a package that
needed 27.1 to compile would be uninstallable for most people until their CI
upgraded.

## Notes on use

Read regions from the current `FoldInfo` on every build rather than caching
them. They arrive after the first layout pass and change as the device folds.

Prefer `pose` over `hingeAngle` for layout decisions. Apple documents the
angle's "rate and granularity" as system policy that can change, so the
platform's own classification is the more stable signal. `FoldPose` mirrors
`UIHingeStatus` one for one — postures like "book" or "tabletop" are Android
foldable vocabulary and are not reported by this device.

Lay out against size classes rather than orientation. The inner display does
not honour an app's supported interface orientations.

## Verification

Every native symbol this package calls was verified on 2026-09-20 by two
independent passes that agree: Objective-C runtime introspection on a booted
iPhone Duo simulator running iOS 27.1, and the iOS 27.1 SDK headers. Exact type
encodings and header quotes are recorded in [`API_NOTES.md`](API_NOTES.md), and
both passes are reproducible — the runtime probe ships as
`integration_test/native_api_probe_test.dart`.

The Duo simulator has been exercised shut. The device itself has not shipped,
so nothing here has run on physical hardware.
[`docs/manual-tests.md`](docs/manual-tests.md) tracks what has been checked on
the simulator and what has not.

## License

See [LICENSE](LICENSE).
