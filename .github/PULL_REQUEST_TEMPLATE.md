<!--
Thanks for this. CONTRIBUTING.md has the full picture; this is the short
version. Delete whatever does not apply.
-->

## What this changes, and why

<!-- What went wrong without it, not just what the diff does. The CHANGELOG is
written in that voice and this is where its text usually comes from. -->

Fixes #

## Verified on

<!-- Be specific and be honest. "Emulator only" and "not tested on hardware"
are perfectly acceptable answers — the README has a column for exactly that.
An unverified claim is the only thing that is not. -->

- [ ] Unit / widget tests
- [ ] iOS simulator — which:
- [ ] Android emulator — which:
- [ ] Physical device — which:
- [ ] Not verified on a platform, and here is why:

## Checks

- [ ] `flutter analyze` is clean, and `flutter test` passes
- [ ] `dart format` has been run over `lib test example/lib example/test example/integration_test`
- [ ] The example still analyses and tests
- [ ] A fix comes with the test that reproduces the bug

## If it touches native code

- [ ] Every new platform symbol is recorded in `API_NOTES.md` with its source and the date it was checked
- [ ] Anything that could not be verified carries `// UNVERIFIED` and a line in that file
- [ ] The Kotlin (`:bifold:test`) or Swift (`RunnerTests`) tests still pass

## If it touches the public API

- [ ] Nothing published in 1.0.0 was removed or changed without a deprecation and a CHANGELOG migration line
- [ ] No new value was added to an existing enum, or if it was, the break is called out above
- [ ] No capability claims more than the platform actually told us
- [ ] Capability, availability and current state are still three separate things
- [ ] A new README snippet has a matching entry in `test/readme/readme_examples_test.dart`
- [ ] No consumer needs a `Platform.isIOS` or `Platform.isAndroid` branch to use it
