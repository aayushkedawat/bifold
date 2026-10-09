# bifold

[![pub package](https://img.shields.io/pub/v/bifold.svg)](https://pub.dev/packages/bifold)
[![CI](https://github.com/aayushkedawat/bifold/actions/workflows/ci.yml/badge.svg)](https://github.com/aayushkedawat/bifold/actions/workflows/ci.yml)
[![pub points](https://img.shields.io/pub/points/bifold)](https://pub.dev/packages/bifold/score)
[![platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey.svg)](https://pub.dev/packages/bifold)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Fold awareness for Flutter, on iPhone Duo and Android foldables. Where the fold
is, how far the device is open, which display you are on, and what the hardware
can do — behind one API, so your code never asks which platform it is running
on.

On every device without a fold — ordinary phones, iPad, web, desktop — it
reports a well-defined "no fold" state and never throws. Safe to adopt in an app
that ships everywhere.

<p align="center">
  <img
    src="https://raw.githubusercontent.com/aayushkedawat/bifold/main/media/bifold-animation.gif"
    alt="A Flutter layout tracking the hinge as the device folds: two panes separating at the crease, with the hinge angle and pose updating live."
    width="420">
</p>

## Install

```yaml
dependencies:
  bifold: ^1.0.0
```

Wrap your app once, near the root. There is no other setup — no `Info.plist`
entry, no permissions, no native code to add.

```dart
import 'package:bifold/bifold.dart';

void main() => runApp(const BifoldScope(child: MyApp()));
```

## Reading fold state

`Bifold.of(context)` returns a `FoldInfo` and rebuilds the caller when it
changes.

```dart
Widget build(BuildContext context) {
  final info = Bifold.of(context);

  return Column(
    children: [
      Text('Pose: ${info.pose.name}'),
      if (info.hingeAngleDegrees case final degrees?)
        Text('Open to ${degrees.toStringAsFixed(0)}°'),
    ],
  );
}
```

If you only need one part of the state, ask for that part. A widget using
`Bifold.poseOf(context)` does not rebuild when the hinge angle moves — which, on
a hinge streaming at sensor rate, is the difference between one rebuild and
hundreds.

```dart
Bifold.poseOf(context);        // FoldPose
Bifold.hingeAngleOf(context);  // double?, radians
Bifold.regionsOf(context);     // List<FoldRegion>
Bifold.displayOf(context);     // FoldDisplay
```

Outside the widget tree:

```dart
await Bifold.current;   // one-shot read
Bifold.stream;          // Stream<FoldInfo>
Bifold.listenable;      // ValueListenable<FoldInfo>, for a controller or bloc
```

## What the device is doing vs what it can do

Two different questions, two different answers. `FoldInfo` says what the device
is doing *now*. `BifoldCapabilities` says what it can *ever* do.

```dart
final can = Bifold.capabilitiesOf(context);

if (can.hasHingeAngle) {
  // Worth building something that reacts to the angle on this device.
}
```

Keeping them apart matters: a foldable folded shut still *has* a fold, and a
hinge sensor that is present but silent is a missing reading rather than a
missing sensor.

**A false `hasX` does not mean "no".** Every capability is really three states,
because "this device has no hinge" and "nothing has reported a hinge yet" have
very different consequences at startup.

```dart
switch (can.statusOf(FoldFeature.halfOpenedPosture)) {
  case CapabilityStatus.supported:   // proven yes
  case CapabilityStatus.unsupported: // proven no
  case CapabilityStatus.unknown:     // nobody has said yet
}
```

`hasX` is true only for `supported`. Two predefined values make the difference
explicit: `BifoldCapabilities.unresolved` (nothing established) and
`BifoldCapabilities.none` (established: no fold support of any kind). The same
distinction exists on fold state as `FoldInfo.isResolved` — gate a startup
layout on that rather than on `isFoldable`, or it can flash the wrong way.

Three rules the capability model follows, which is why it can be trusted:

- An observation is evidence **for**, never against. Seeing a half-opened
  posture proves the device can report one; never seeing it proves nothing.
- Only an authoritative platform query produces `unsupported`.
- `supported` is sticky for the process. A closed foldable reports no folding
  feature at all, so nothing is allowed to take a capability away.

`can.sourceOf(feature)` returns which platform signal decided an answer, for
diagnostics. Never parse it.

## Layout

| I want to… | Use |
|---|---|
| put two panes either side of the fold | `BifoldSplit` |
| lay out a grid that never bends a tile | `BifoldGrid` |
| move my navigation as the device opens | `BifoldScaffold` |
| keep a dialog off the crease | `bifoldAnchorPoint` |

### `BifoldSplit`

```dart
BifoldSplit(
  start: const MessageList(),
  end: const MessageDetail(),
)
```

When the device is part-way open and an active fold crosses the widget, the
panes are placed either side of the crease, clear of its margins. Otherwise they
fall back to `fallback`:

| `BifoldSplitFallback` | behaviour |
|---|---|
| `adaptive` (default) | side by side where there is room, stacked where there is not |
| `stack` | one above the other |
| `sideBySide` | side by side, split evenly |
| `startOnly` | show `start`, drop `end` |

The fallback is the common case, not the exception — a fold is only *active*
while the device is part-way open, so a flat open display, a shut one, a tablet,
a desktop window and an ordinary phone all take that path. `adaptive` reads
`FoldInfo.isRegular` where the platform reports size classes and the available
width against `kBifoldRegularWidthBreakpoint` where it does not, so the same
widget gives two panes on an open foldable and one on a phone with no code in
between.

### `BifoldGrid`

```dart
BifoldGrid(
  tileExtent: 160,
  children: photos.map(PhotoTile.new).toList(),
)
```

Treats an active fold as a hard break, so no tile is ever drawn bent across the
crease. With no active fold it is an ordinary wrapping grid, so it is safe to use
unconditionally.

### `BifoldScaffold`

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

A bottom `NavigationBar` when the layout is compact, a `NavigationRail` when it
is roomy — and the rail goes on whichever edge the platform says it prefers for
its own vertical bar, so app navigation and system UI end up on the same side.
Until the platform has answered it renders the body with no navigation rather
than guessing and flashing; pass `showNavigationBeforeResolved: true` to opt out.

### `bifoldAnchorPoint`

```dart
showDialog(
  context: context,
  anchorPoint: bifoldAnchorPoint(context),
  builder: (context) => const AlertDialog(title: Text('Hello')),
);
```

Places a dialog in whichever half has more room instead of straddling the
crease. Returns null when there is nothing to avoid, so it is safe to pass
unconditionally.

## The other display

Content on the display facing the rear camera, so the person being filmed can
see their framing — or read a teleprompter.

| | What happens | Where |
|---|---|---|
| `present()` | a second view appears on the other display; your app stays put | both platforms |
| `transferActivity()` | the whole app moves across | Android only |

The presented content runs in its own Flutter engine, so it needs its own
entrypoint. Give it its own `BifoldScope`: a second engine is a separate isolate
and does not inherit the one from `main`, so without a scope that content cannot
react to the hinge.

```dart
@pragma('vm:entry-point')
void rearDisplayMain() => runApp(const BifoldScope(child: SubjectView()));

void main() => runApp(const BifoldScope(child: MyCameraApp()));
```

```dart
// False means the system said no, which is not an error.
await BifoldRearDisplay.present(entrypoint: 'rearDisplayMain');
await BifoldRearDisplay.end();
```

### Capability, availability and state

Three different questions, and collapsing any two produces a UI that lies:

- **capability** decides whether the control **exists** — stable for the life of
  the app, so nothing keyed on it flickers;
- **availability** decides whether it is **enabled** — it moves with the capture
  session, so the control dims rather than disappearing;
- **state** decides what it **says and does** — start, or stop.

```dart
if (Bifold.capabilitiesOf(context).hasRearDisplay) {
  StreamBuilder<RearDisplayAvailability>(
    stream: BifoldRearDisplay.availability,
    initialData: RearDisplayAvailability.unresolved,
    builder: (context, snapshot) {
      final now = snapshot.data ?? RearDisplayAvailability.unresolved;
      final running = now.presentation == RearDisplayStatus.active;
      return Switch(
        value: running,
        onChanged: now.presentation == RearDisplayStatus.available || running
            ? (on) => on
                ? BifoldRearDisplay.present(entrypoint: 'rearDisplayMain')
                : BifoldRearDisplay.end()
            : null,
      );
    },
  );
}
```

`RearDisplayStatus` has four values rather than a boolean, because "this device
cannot" and "it could, but not right now" call for different UI:

| Status | Meaning | Do |
|---|---|---|
| `unsupported` | the device cannot | hide the control |
| `unavailable` | supported, not possible now | disable it |
| `available` | ready to start | enable it |
| `active` | running | offer to stop |

`isResolved` separates those four from a fifth situation — nothing has reported
yet — so a control can wait instead of hiding.

**The system is in charge throughout.** Asking is not being shown: it decides
whether a session runs and can end one at any time, and on iOS it will not
present anything without an active camera capture session. Treat the feature as
an enhancement — the app must stay usable when it never appears, which is also
what happens on every single-display device.

> `BifoldCaptureAccessory` is the iOS-only predecessor, deprecated in 1.0.0 and
> removed in 2.0.0. It keeps working. To migrate: `register()` plus
> `setEnabled(true)` becomes `present()`, `unregister()` becomes `end()`, and the
> boolean availability stream becomes the four-state one above.

## Testing

Fold-aware layouts can be tested on any machine — no simulator, no iOS SDK, no
channel mocking.

```dart
testWidgets('reader splits across the fold', (tester) async {
  await tester.pumpWidget(
    BifoldScope.fake(
      info: FoldInfoFakes.partiallyOpen(viewSize: const Size(800, 1000)),
      capabilities: BifoldCapabilityFakes.book(),
      child: const MyReader(),
    ),
  );
});
```

`FoldInfoFakes.poseMatrix(size)` drives every pose in one table-based test,
including the two cases most layouts get wrong: a resolved non-foldable phone,
and a foldable whose hinge sensor is present but silent.

Capability profiles are named after device *shapes*, never products: `book()`,
`flip()`, `dualScreen()`, `bookWithTransfer()`, `flat`, `unopenedFoldable()`.
`RearDisplayFakes` covers the five rear-display situations.

To drive updates over time, install `FakeBifoldPlatform`:

```dart
final platform = FakeBifoldPlatform(initial: FoldInfoFakes.closed);
BifoldPlatform.instance = platform;
addTearDown(platform.dispose);

platform.emit(FoldInfoFakes.partiallyOpen(viewSize: size));
platform.emitRearDisplay(RearDisplayFakes.available);
platform.emitError(StateError('the platform fell over'));
```

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
| Android hinge angle | API 30+, with a hinge angle sensor |

`androidx.window` is pinned to the version Flutter's own Android embedding
already resolves, so adding `bifold` cannot pull your app into a conflict with
the engine. No permissions are requested.

The fold symbols ship in the iOS 27.1 SDK, but `bifold` resolves them through
the Objective-C runtime rather than linking them. One binary builds on an older
Xcode and still reports fold state on a device that has the APIs — a package
needing 27.1 to compile is uninstallable for anyone whose CI has not upgraded.

## Gotchas

**Never cache regions.** They arrive after the first layout pass and change as
the device folds. Read them from the current `FoldInfo` every build.

**`frame` already includes `margins`.** Lay out against `frame` directly; do not
inflate it again. `reservedRect` is the bare hardware if you need it.

**Prefer `pose` over `hingeAngle` for layout.** Apple documents the angle's rate
and granularity as system policy that can change, and says to use hinge data for
animation rather than layout decisions. Lay out with size classes and `pose`;
animate with the angle.

**Lay out against size classes, not orientation.** On iOS the inner display does
not honour an app's supported interface orientations. Android has no UIKit size
classes, so `bifold` derives them from the window against the Material
breakpoints (600dp wide, 480dp tall).

**On Android, `pose` is `unknown` when shut — never `closed`.** `FoldingFeature`
has only `FLAT` and `HALF_OPENED`, and a closed device reports no folding feature
at all. `isFoldable` still answers correctly there, because it comes from a
static device feature rather than an observation.

**On Android, region margins are zero** — the platform reports hardware bounds
with no clearance, so `frame` and `reservedRect` are the same rectangle. On iOS
the frame arrives with clearance built in.

**On Android, `display` is never `outer`.** Android cannot distinguish a closed
foldable from a cover display from a non-foldable, so it reports `none` rather
than guessing. Branch on `pose` and size classes instead.

## What is verified where

A ✅ means someone ran it and recorded the result in
[`doc/manual-tests.md`](doc/manual-tests.md). A blank means nobody has checked it
on this build, which is not the same as it being broken.

| | iOS | Android |
|---|---|---|
| Native symbols checked against SDK/artifacts | ✅ | ✅ |
| Native code covered by automated tests | ✅ 6 Swift | ✅ 13 Kotlin |
| Fold state on a simulator / emulator | ✅ | ✅ |
| Open, half-open and closed | ✅ | ✅ |
| Hinge angle | ✅ | ✅ (injected) |
| Size classes | ✅ | ✅ |
| No capability claims more than the fold does | ✅ in CI | ✅ in CI |
| Reserved regions | ⚠️ never observed | n/a — margins always zero |
| Rear display: starting a session | ⚠️ needs a capture session | ✅ (emulator) |
| Rear display: ending a session | | ⚠️ no callback on the emulator |
| Rear display: transfer | n/a — no iOS equivalent | ⚠️ unverified |
| Physical hardware | ❌ | ❌ |

**Nothing in this package has run on a physical foldable, on either platform.**
The iPhone Duo ships on 23 October 2026; the Android side has been exercised on
emulators only. Three gaps are worth stating rather than leaving to be inferred:

- **Reserved regions have never been observed on iOS.** The simulator does not
  emit them, so the decode path, coordinate space and margin handling are
  verified against the SDK headers and exercised by unit tests with synthetic
  geometry — not against a real reading.
- **Ending a rear-display session is unverified.** On the `android-37.2`
  emulator `close()` produced no `onSessionEnded` callback and the area kept
  reporting `active`. That value is passed through rather than replaced with an
  `available` the platform is not reporting.
- **`transferActivity()` has never completed a round trip.**

If a real device disagrees with any of this, please
[file a report](https://github.com/aayushkedawat/bifold/issues) —
`Bifold.diagnosticReport()` prints what to paste in. It builds a string and
returns it; **nothing is transmitted**, and it carries no identifier beyond the
model string. Device reports are how the ❌ rows above change.

Every symbol this package calls, with its source and the date it was verified,
is recorded in [`API_NOTES.md`](API_NOTES.md), along with what remains
unverified.

## Also included

- **`BifoldDebugOverlay`** — draws every reserved region the platform reports,
  solid when active and faint when not. Usually the answer to "why didn't my
  layout react?".
- **`BifoldDisplayFeatures`** — republishes the fold as
  `MediaQuery.displayFeatures`, so packages written for Android foldables, and
  Flutter's own dialog positioning, work on iOS too. Opt in; it stands down
  automatically if the engine ever populates the field itself.
- **`BifoldArrangement`** — asks the platform where *it* would place two panes,
  measured from a real arrangement rather than modelled.

Full API documentation is on
[pub.dev](https://pub.dev/documentation/bifold/latest/).

## License

MIT. See [LICENSE](LICENSE).

Maintained in my spare time — if it saves you some,
[sponsorship](https://github.com/sponsors/aayushkedawat) funds bug fixes and
keeping up with Flutter releases.
