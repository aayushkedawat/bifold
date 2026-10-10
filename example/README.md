# bifold example

A Flutter app that exercises every part of `bifold` on a foldable: live fold
state, the resolved capability set with the evidence behind each claim, the
fold-aware layout widgets, the rear display, and the diagnostic report.

Run it on an iOS foldable simulator or an Android foldable emulator:

```sh
cd example
flutter run
```

## The smallest thing that works

Wrap the app once. There is no other setup — no `Info.plist` entry, no
permissions, no native code to add.

```dart
import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';

void main() => runApp(const BifoldScope(child: MyApp()));
```

Then read the fold wherever you need it. `Bifold.of(context)` rebuilds the
caller when the state changes, and reports a well-defined "no fold" state on an
ordinary phone rather than throwing:

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
`Bifold.poseOf(context)` does not rebuild when the hinge angle moves — on a
hinge streaming at sensor rate, that is the difference between one rebuild and
hundreds:

```dart
Bifold.poseOf(context);        // FoldPose
Bifold.hingeAngleOf(context);  // double?, radians
Bifold.regionsOf(context);     // List<FoldRegion>
Bifold.displayOf(context);     // FoldDisplay
```

The hinge gauge at the top of this app is the widget where that matters most,
because it is the one redrawn at sensor rate. It takes `radians` and `pose`
rather than a whole `FoldInfo`, so it watches exactly those two aspects and a
change to the regions or the size class does not rebuild it.

The **Reads** tab makes the difference visible: every card there counts its own
builds, so you can fold the device and watch `Bifold.of` climb while the scoped
readers sit still.

## A two-pane layout that follows the hinge

`BifoldSplit` aligns its panes to the fold while the device is part-way open,
and falls back to `BifoldSplitFallback.adaptive` otherwise — side by side where
there is room, stacked where there is not. That covers a book foldable, a flip
foldable, an ordinary phone, a tablet and desktop without a single platform
check:

```dart
BifoldSplit(
  start: const MessageList(),
  end: const MessageDetail(),
)
```

## Asking what the device can do

Capability is a separate question from current state, and the two never share a
field. `Bifold.capabilities` answers the first:

```dart
final capabilities = Bifold.capabilities;

capabilities.hasFold;              // is there a hinge at all
capabilities.hasHingeAngle;        // is there an angle source to read
capabilities.hasHalfOpenedPosture; // can it report part-way open
capabilities.hasRearDisplay;       // can content go on the outer display
```

Before the platform has reported, each of those is `unknown` rather than
`false`: `capabilities.isResolved` says which, and
`capabilities.statusOf(feature)` tells "no" apart from "not yet known". Await
`Bifold.capabilitiesReady` outside the widget tree if you need the resolved set.

## What is in this app

| Tab | What it shows |
|---|---|
| **Reader** | Two pages of a book laid out either side of the fold: `BifoldSplit` and `bifoldAnchorPoint` |
| **Gallery** | `BifoldGrid` against a plain `GridView`, so rows breaking at the crease are visible side by side rather than described |
| **Studio** | The rear display: availability, presenting alongside the app, and moving the whole app across |
| **Inspector** | Every field of `FoldInfo` and every reserved region in full, with no interpretation — the tab to screenshot in a bug report |
| **Can do** | The resolved capability set with the platform signal behind each answer, and `Bifold.diagnosticReport()` |
| **Reads** | A live build counter per accessor, showing which reads rebuild and which do not, plus `BifoldArrangement.measure()` — where the platform itself would put two panes |
| **Apps** | Three small consumers written against the public API with no platform checks at all — a hinge-reactive creature, a two-pane UI, and a rear-display camera |

The full source is on
[GitHub](https://github.com/aayushkedawat/bifold/tree/main/example).
