# Contributing to bifold

Thanks for looking. This is a small package maintained in spare time, so the
most useful contributions are the ones that need the least coordination.

## The most valuable thing you can send

**A device report.** Nothing in this package has run on a physical foldable, on
either platform — the iPhone Duo and the Android side have only ever been
exercised on simulators and emulators. The `❌ Physical hardware` row in the
README's [verification matrix](README.md#what-is-verified-where) changes when
somebody with real hardware tells us what it did.

If you have a foldable, run the example app, open a
[device report](https://github.com/aayushkedawat/bifold/issues/new?template=device_report.yml)
and paste in `Bifold.diagnosticReport()`. It builds a string and returns it;
**nothing is transmitted**, and it carries no identifier beyond the model
string. Read it before you post it if you would rather not share the model.

A report saying "everything matched" is worth as much as one saying it didn't.

## Before you open a pull request

- **Bug fix, docs, a test:** go ahead, no need to ask.
- **Anything that changes the public API:** open an issue first. 1.0.0 is a
  stability promise, and a change that breaks an exhaustive `switch` in
  somebody's app costs them a release. Additive is nearly always possible.
- **A new dependency:** ask first. The package depends on
  `plugin_platform_interface` and nothing else, which is deliberate.

## The rules the code already follows

These are not style preferences; each one exists because breaking it produced a
bug that shipped.

1. **Never invent a platform API.** Every Swift, Kotlin and Jetpack symbol is
   verified against SDK headers, SDK sources or official docs, and recorded in
   [`API_NOTES.md`](API_NOTES.md) with its source and the date it was checked.
   Anything unverified carries a `// UNVERIFIED` comment and a line in that
   file. `scripts/verify-sdk.sh` prints the iOS declarations to paste in.
2. **Never throw because a platform lacks a feature.** Unsupported is a value:
   `FoldInfo.none`, `BifoldCapabilities.none`. A `MissingPluginException` on web
   or desktop is an expected path, not an error.
3. **A capability never claims more than we know.** Each one is `supported`,
   `unsupported` or `unknown`. Only an authoritative static signal may produce
   `unsupported` — not seeing something is never evidence against it, because a
   shut foldable reports no folding feature at all. Positive evidence is sticky
   within the process. CI asserts that no capability claims support while the
   fold itself is unestablished.
4. **Capability, availability and current state never share a field.** What the
   hardware *can* do, what can be used *right now*, and what is happening *this
   frame* are three questions. Conflating two of them is the mistake this API
   exists to prevent.
5. **No `Platform.isIOS` in consumer code.** If an example or a downstream
   consumer needs a platform branch, the abstraction has failed and that is the
   bug to fix. The three consumers in `example/lib/downstream/` exist as the
   standing proof of this.
6. **Don't break 1.0.0.** Deprecate with a migration line in the CHANGELOG and
   keep the old symbol working. `BifoldCaptureAccessory` is the worked example.

## Running what CI runs

```sh
flutter pub get
flutter analyze                 # public_member_api_docs is on, so this also
                                # catches undocumented public members
dart format --output=none --set-exit-if-changed \
  lib test example/lib example/test example/integration_test
flutter test
(cd example && flutter test && flutter analyze)
flutter pub publish --dry-run   # catches a native source left out of the archive
```

The native tests need a platform toolchain:

```sh
# Kotlin, from the example's Gradle project, which resolves the plugin as a module
(cd example/android && ./gradlew :bifold:test --console=plain)

# Swift, against the real native implementation on a simulator
(cd example && xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RunnerTests)
```

Flutter is pinned to **3.44.4** in CI, because that is the only version the
pubspec claims has been exercised.

## Tests

- **A bug fix ships with the test that reproduces it.** Each of the six bugs
  fixed in 1.0.0 was reproduced by a test before being fixed, and those tests
  ship.
- **Decision logic belongs in Dart.** Resolution, precedence, normalization and
  posture derivation are pure Dart and unit-tested with no platform at all. Use
  `BifoldScope.fake` and `BifoldCapabilityFakes` rather than reaching for an
  emulator.
- **A new README snippet needs a line in
  [`test/readme/readme_examples_test.dart`](test/readme/readme_examples_test.dart).**
  That file compile-checks the documentation; it cannot detect a snippet nobody
  copied into it.
- **Anything that can only be checked by hand** goes in
  [`doc/manual-tests.md`](doc/manual-tests.md), with the exact commands —
  including the `adb` lines that drive the emulator's posture and hinge sensor.

## Pull requests

Keep them small and scoped to one thing. Commit subjects follow the pattern in
`git log`: a lowercase prefix naming the area, then what changed and ideally
why — `fix: let a capability change reach Dart on its own`, not `fix bug`. The
CHANGELOG is written in the same voice: what changed, and what went wrong
without it.

Describe what you verified and on what. "Emulator only" and "not tested" are
perfectly acceptable answers — the README has a column for exactly that. An
unverified claim is the only thing that isn't.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Reports go
to hi@aayou.sh.
