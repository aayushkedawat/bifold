# bifold

[![pub package](https://img.shields.io/pub/v/bifold.svg)](https://pub.dev/packages/bifold)
[![CI](https://github.com/aayushkedawat/bifold/actions/workflows/ci.yml/badge.svg)](https://github.com/aayushkedawat/bifold/actions/workflows/ci.yml)
[![pub points](https://img.shields.io/pub/points/bifold)](https://pub.dev/packages/bifold/score)
[![likes](https://img.shields.io/pub/likes/bifold)](https://pub.dev/packages/bifold/score)
[![platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey.svg)](https://pub.dev/packages/bifold)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Fold awareness for Flutter apps on the foldable iPhone and on Android
foldables: where the fold is, how far the device is open, which display you are
on, and where hardware is in the way.

One API for both. The same `FoldInfo`, the same layout widgets and the same
test fakes work on either platform, and your code never asks which one it is
running on.

On every device without a fold — ordinary phones, older iOS, iPad, web and
desktop — it reports a well-defined "no fold" state and never throws, so it is
safe to adopt in an app that ships everywhere.

```dart
void main() => runApp(const BifoldScope(child: MyApp()));

// anywhere below:
final info = Bifold.of(context);
if (info.division != null) {
  // The display is creased right now.
}
```

## Contents

- [Install](#install)
- [Which widget do I want?](#which-widget-do-i-want)
- [Reading fold state](#reading-fold-state)
- [Layout](#layout)
- [Camera](#camera)
- [Diagnostics](#diagnostics)
- [Testing](#testing)
- [API reference](#api-reference)
- [Requirements](#requirements)
- [Gotchas](#gotchas)

## Install

```yaml
dependencies:
  bifold: ^0.1.0
```

Then wrap your app once, near the root:

```dart
import 'package:bifold/bifold.dart';

void main() => runApp(const BifoldScope(child: MyApp()));
```

Everything else reads from that scope. There is no other setup, no
`Info.plist` entry, and no native code to add.

## Which widget do I want?

| I want to… | Use |
|---|---|
| know the fold state anywhere in my tree | `Bifold.of(context)` |
| put two panes either side of the fold | `BifoldSplit` |
| lay out a grid that never bends a tile | `BifoldGrid` |
| move my navigation as the device opens | `BifoldScaffold` |
| keep a dialog off the crease | `bifoldAnchorPoint` |
| show content to the person I'm filming | `BifoldCaptureAccessory` |
| see what the platform is actually reporting | `BifoldDebugOverlay` |
| make Android-foldable packages work here | `BifoldDisplayFeatures` |
| match the platform's own split exactly | `BifoldArrangement` |
| test my layout with no device | `BifoldScope.fake` + `FoldInfoFakes` |

## Reading fold state

`Bifold.of(context)` returns a `FoldInfo` and rebuilds the caller whenever it
changes.

```dart
Widget build(BuildContext context) {
  final info = Bifold.of(context);

  return Column(
    children: [
      Text('Pose: ${info.pose.name}'),
      if (info.hingeAngleDegrees case final degrees?)
        Text('Open to ${degrees.toStringAsFixed(0)}°'),
      Text('On the ${info.display.name} display'),
    ],
  );
}
```

Outside the widget tree, use `Bifold.current` for a one-shot read or
`Bifold.stream` for updates:

```dart
final subscription = Bifold.stream.listen((info) {
  analytics.log('fold', {'pose': info.pose.name});
});
```

`Bifold.maybeOf(context)` returns null instead of throwing when there is no
`BifoldScope` above, which is useful in a widget that may be used either way.

## Layout

### Two panes across the fold — `BifoldSplit`

```dart
BifoldSplit(
  start: PageView(controller: leftController),
  end: PageView(controller: rightController),
)
```

When the device is part-way open and an active division crosses the widget, the
panes are placed either side of the crease, clear of its margins. Otherwise
they fall back to `fallback`:

| `BifoldSplitFallback` | behaviour |
|---|---|
| `stack` (default) | one above the other |
| `sideBySide` | side by side, split evenly |
| `startOnly` | show `start`, drop `end` |

```dart
BifoldSplit(
  fallback: BifoldSplitFallback.sideBySide,
  spacing: 16,
  start: const MessageList(),
  end: const MessageDetail(),
)
```

### A grid that never bends a tile — `BifoldGrid`

```dart
BifoldGrid(
  tileExtent: 160,
  spacing: 8,
  padding: const EdgeInsets.all(12),
  children: photos.map(PhotoTile.new).toList(),
)
```

Tiles fill the space before the crease, then resume after it. No tile is drawn
across the fold. With nothing to avoid it behaves as an ordinary wrapping grid,
so it is safe to use unconditionally.

### Navigation that follows the fold — `BifoldScaffold`

```dart
BifoldScaffold(
  appBar: AppBar(title: const Text('Inbox')),
  selectedIndex: index,
  onDestinationSelected: (i) => setState(() => index = i),
  destinations: const [
    BifoldDestination(icon: Icon(Icons.inbox), label: 'Inbox'),
    BifoldDestination(icon: Icon(Icons.send), label: 'Sent'),
  ],
  body: const MessageList(),
)
```

A bottom `NavigationBar` on a compact layout — the outer display, or any
ordinary phone — and a `NavigationRail` on a regular one, which is what the
inner display reports. The rail goes on whichever edge the platform prefers for
its own vertical bar, so app navigation and system UI share a side rather than
bracketing your content.

With fewer than two destinations the navigation is omitted rather than rendered
as a single useless item.

### Keep dialogs off the crease — `bifoldAnchorPoint`

```dart
showDialog<void>(
  context: context,
  anchorPoint: bifoldAnchorPoint(context),
  builder: (context) => const AlertDialog(title: Text('Saved')),
);
```

Places the dialog in whichever half has more room. Returns null when there is
nothing to avoid, which is exactly what `showDialog` expects by default — so
pass it unconditionally.

## Camera

### Content on the outer display — `BifoldCaptureAccessory`

With the device open and a capture session running, the system can show your
content on the outer display, facing whoever is being filmed — a framing
preview, or a teleprompter.

The accessory renders in its own Flutter engine, so it needs its own entrypoint:

```dart
@pragma('vm:entry-point')
void captureAccessoryMain() => runApp(const SubjectView());

void main() => runApp(const BifoldScope(child: MyCameraApp()));
```

Register it once your camera UI is up, and follow what the system decides:

```dart
if (await BifoldCaptureAccessory.isSupported) {
  await BifoldCaptureAccessory.register(entrypoint: 'captureAccessoryMain');
  await BifoldCaptureAccessory.setEnabled(true);
}

BifoldCaptureAccessory.availability.listen((available) {
  // The system decides whether and where it appears.
});

// when the camera closes:
await BifoldCaptureAccessory.unregister();
```

`setEnabled(true)` says your app *would like* the accessory shown;
`availability` reports whether the system says it *can* be. It will not appear
without an active capture session, and your app must stay fully functional when
it never appears.

## Diagnostics

### See what the platform is reporting — `BifoldDebugOverlay`

```dart
MaterialApp(
  builder: (context, child) => BifoldDebugOverlay(child: child!),
  home: const MyHomePage(),
)
```

Draws every reserved region: a filled band for the hardware, an outline for the
hardware plus its clearance, solid when active and faint when not. That
active/inactive distinction is usually the answer to "why didn't my layout
react?". Ignores pointer events, so the app underneath stays usable.

Wire `enabled` to a debug switch rather than removing the widget, so the tree
shape does not change when you toggle it.

### Bridge to `MediaQuery.displayFeatures` — `BifoldDisplayFeatures`

Flutter populates `displayFeatures` only on Android, so packages written for
Android foldables — and Flutter's own dialog positioning — see nothing on iOS.
Opt in and they work:

```dart
MaterialApp(
  builder: (context, child) => BifoldDisplayFeatures(child: child!),
  home: const MyHomePage(),
)
```

The widget stands down automatically if the engine ever populates the field
itself, so it will not fight a future Flutter release.

### Match the platform's own split — `BifoldArrangement`

`BifoldSplit` positions panes from the reported fold. This asks the platform
where *it* would put them, measured from a real arrangement rather than
modelled:

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

Measuring attaches an empty, non-interactive view controller for the duration.
Call `release()` when finished.

### Report a bug — `Bifold.debugDescribeNativeApi`

```dart
final report = await Bifold.debugDescribeNativeApi();
```

Returns what the running OS actually exposes — real selector names, type
encodings and class members — which is far more useful in an issue than a
version number.

## Testing

This is the part most fold packages leave out. `BifoldScope.fake` and
`FoldInfoFakes` exercise a fold-aware layout on any machine: no simulator, no
iOS SDK, no channel mocking.

```dart
testWidgets('reader splits across the fold', (tester) async {
  await tester.pumpWidget(
    BifoldScope.fake(
      info: FoldInfoFakes.partiallyOpen(viewSize: const Size(800, 1000)),
      child: const MyReader(),
    ),
  );

  expect(find.text('Page 2'), findsOneWidget);
});
```

`FoldInfoFakes.poseMatrix(size)` returns every pose for table-driven tests,
including the two that catch real bugs — a flat display that still reports an
*inactive* division, and a crease with zero thickness:

```dart
for (final entry in FoldInfoFakes.poseMatrix(size).entries) {
  testWidgets('lays out when ${entry.key}', (tester) async {
    await tester.pumpWidget(
      BifoldScope.fake(info: entry.value, child: const MyReader()),
    );
    expect(tester.takeException(), isNull);
  });
}
```

Individual fakes: `FoldInfoFakes.closed`, `.fullyOpen()`, `.partiallyOpen()`,
`.partiallyOpenVertical()`, `.unsupported`.

## API reference

### `FoldInfo`

| member | type | meaning |
|---|---|---|
| `isFoldable` | `bool` | the device has a fold this package can report on |
| `pose` | `FoldPose` | `closed`, `partiallyOpen`, `fullyOpen`, `unknown` |
| `hingeAngle` | `double?` | hinge angle in radians, null if unreported |
| `hingeAngleDegrees` | `double?` | the same value in degrees |
| `display` | `FoldDisplay` | `outer`, `inner`, `none` |
| `regions` | `List<FoldRegion>` | every reserved region, active or not |
| `division` | `FoldRegion?` | the active fold, or null when not creased |
| `activeRegions` | `Iterable<FoldRegion>` | regions whose hardware is in use |
| `horizontalSizeClass` | `FoldSizeClass` | `compact`, `regular`, `unspecified` |
| `verticalSizeClass` | `FoldSizeClass` | as above |
| `isRegular` | `bool` | both axes regular — what the inner display reports |
| `verticalBarEdge` | `VerticalBarEdge` | `leading`, `trailing`, `unspecified` |
| `FoldInfo.unsupported` | `FoldInfo` | the state every non-foldable device reports |

### `FoldRegion`

| member | type | meaning |
|---|---|---|
| `kind` | `RegionKind` | `division` (the fold) or `occlusion` (e.g. a camera) |
| `frame` | `Rect` | the whole area to avoid — **margins included** |
| `reservedRect` | `Rect` | the hardware itself, `frame` minus `margins` |
| `margins` | `EdgeInsets` | how much of `frame` is clearance |
| `isActive` | `bool` | whether the hardware is currently in use |
| `isSeparating(Size)` | `bool` | whether it actually divides the display |
| `isHorizontal` | `bool` | whether it runs across rather than down |

### `ArrangementMeasurement`

`primary` and `secondary` are `ArrangementPane`s, each with `bounds` and
`isVisible`; `axis` is an `ArrangementAxis`; `isSplit` is true when the platform
shows two panes rather than collapsing to one.

## Requirements

| | |
|---|---|
| Flutter | 3.27.0+ |
| Dart | 3.6.0+ |
| iOS deployment target | 15.0 |
| iOS fold reporting | iOS 27.1+ on a foldable device |
| Xcode to build | **26.x or newer — 27.1 is not required** |
| Android `minSdk` | 24 |
| Android fold reporting | a device Jetpack WindowManager reports a fold for |
| Android hinge angle | API 30+, on a device with a hinge angle sensor |

The Android side uses `androidx.window` 1.2.0, pinned to the version Flutter's
own Android embedding already resolves, so adding `bifold` cannot pull your app
into a version conflict with the engine. It asks for no permissions.

The fold symbols ship in the iOS 27.1 SDK, but `bifold` resolves them through
the Objective-C runtime rather than calling them directly. One binary builds on
an older Xcode and still reports fold state on a device that has the APIs. That
matters in practice: a package needing 27.1 to compile is uninstallable for
anyone whose CI has not upgraded.

## Gotchas

**Never cache regions.** They arrive after the first layout pass and change as
the device folds. Read them from the current `FoldInfo` on every build.

**`frame` already includes `margins`.** The platform reports the frame with its
clearance built in, so laying out against `frame` is correct — do not inflate it
again. `reservedRect` is the bare hardware if you need it.

**Prefer `pose` over `hingeAngle` for layout.** Apple documents the angle's
"rate and granularity" as system policy that can change, so the platform's own
classification is the more stable signal.

**Lay out against size classes, not orientation.** On iOS the inner display
does not honour an app's supported interface orientations. On Android there are
no UIKit-style size classes at all, so `bifold` derives them from the current
window against the Material breakpoints — 600dp wide, 480dp tall — which is why
they are reported rather than `unspecified`.

**Pose and angle arrive a moment after the stream is first listened to.** The
platform delivers the initial hinge update asynchronously, so a one-shot
`Bifold.current` at launch may have neither. Until the hinge reports, `pose` is
derived from the regions instead — never wrong, only occasionally late.
`Bifold.of(context)` updates when it lands.

**`FoldPose` mirrors the platform, and never guesses.** Postures like "book"
or "tabletop" are vocabulary neither platform reports, and deriving them from an
angle is the app's decision, not this package's.

**On Android, `pose` is `unknown` when the device is shut — never `closed`.**
`FoldingFeature` has only `FLAT` and `HALF_OPENED`, and a closed device reports
no folding feature at all, which is indistinguishable from a device that does
not fold. `isFoldable` still answers correctly there, because it comes from a
static device feature rather than from an observation.

**On Android, region margins are zero.** The platform reports hardware bounds
with no clearance around them, so `frame` and `reservedRect` are the same
rectangle. On iOS the frame arrives with clearance already built in.

## Verification

### What is verified where

| | iOS | Android |
|---|---|---|
| Native symbols checked against SDK/artifacts | ✅ | ✅ |
| Fold state on a simulator / emulator | ✅ | ✅ |
| Open, half-open and closed | ✅ | ✅ |
| Hinge angle | ✅ | ✅ (injected) |
| Size classes | ✅ | ✅ |
| Physical hardware | ❌ | ❌ |

**Nothing in this package has run on a physical foldable, on either platform.**
The foldable iPhone has not shipped, and the Android side has been exercised on
emulators only. Treat the behaviour as verified where the table says so and
unverified everywhere else, and please
[file a report](https://github.com/aayushkedawat/bifold/issues) if a real device
disagrees — `Bifold.debugDescribeNativeApi()` prints what to paste in.

### iOS

Every Apple symbol was verified by two independent passes that agree:
Objective-C runtime introspection on a booted iPhone Duo simulator running
iOS 27.1, and the iOS 27.1 SDK headers. Exact type encodings and header quotes
are in [`API_NOTES.md`](API_NOTES.md), and both passes are reproducible — the
runtime probe ships as `integration_test/native_api_probe_test.dart`.

### Android

Every symbol was verified by `javap` over the artifacts themselves rather than
from documentation: `window-1.2.0.aar`, `window-java-1.2.0.aar` and
`android.jar`. Behaviour was then checked on a `pixel_9_pro_fold` emulator
running the `android-37.2` system image, across open, half-open and closed,
with hinge angles injected. The observed values are recorded in
[`API_NOTES.md`](API_NOTES.md), along with what remains unverified.

The other half of the promise — that a platform with no fold support reports
`FoldInfo.unsupported` and stays quiet — is verified too, on an ordinary
non-foldable Android emulator.

[`doc/manual-tests.md`](doc/manual-tests.md) has the checklist for both
platforms, with the commands to drive each state.

## License

MIT. See [LICENSE](LICENSE).
